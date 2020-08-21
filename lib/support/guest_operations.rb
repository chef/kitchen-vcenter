require "rbvmomi"
require "net/http" unless defined?(Net::HTTP)

class Support
  # Encapsulate VMware Tools GOM interaction, inspired by github:dnuffer/raidopt
  class GuestOperations
    attr_reader :gom, :vm, :guest_auth, :ssl_verify

    def initialize(vim, vm, guest_auth, ssl_verify = true)
      @gom = vim.serviceContent.guestOperationsManager
      @vm = vm
      @guest_auth = guest_auth
      @ssl_verify = ssl_verify
    end

    def os_family
      return vm.guest.guestFamily == "windowsGuest" ? :windows : :linux if vm.guest.guestFamily

      # VMware tools are not initialized or missing, infer from Guest Id
      vm.config&.guestId&.match(/^win/) ? :windows : :linux
    end

    def linux?
      os_family == :linux
    end

    def windows?
      os_family == :windows
    end

    def delete_dir(dir)
      gom.fileManager.DeleteDirectoryInGuest(vm: vm, auth: guest_auth, directoryPath: dir, recursive: true)
    end

    def process_is_running(pid)
      procs = gom.processManager.ListProcessesInGuest(vm: vm, auth: guest_auth, pids: [pid])
      procs.empty? || procs.any? { |gpi| gpi.exitCode.nil? }
    end

    def process_exit_code(pid)
      gom.processManager.ListProcessesInGuest(vm: vm, auth: guest_auth, pids: [pid])&.first&.exitCode
    end

    def wait_for_process_exit(pid, timeout = 60.0, interval = 1.0)
      start = Time.new

      loop do
        return unless process_is_running(pid)
        break if (Time.new - start) >= timeout

        sleep interval
      end

      raise format("Timeout waiting for process %d to exit after %d seconds", pid, timeout) if (Time.new - start) >= timeout
    end

    def run_program(path, args = "", timeout = 60.0)
      Kitchen.logger.debug format("Running %s %s", path, args)

      pid = gom.processManager.StartProgramInGuest(vm: vm, auth: guest_auth, spec: RbVmomi::VIM::GuestProgramSpec.new(programPath: path, arguments: args))
      wait_for_process_exit(pid, timeout)

      exit_code = process_exit_code(pid)
      raise format("Failed to run '%s %s'. Exit code: %d", path, args, exit_code) if exit_code != 0

      exit_code
    end

    def run_shell_capture_output(command, shell = :auto, timeout = 60.0)
      if shell == :auto
        shell = :linux if linux?
        shell = :cmd if windows?
      end

      if shell == :linux
        tmp_out_fname = format("/tmp/vm_utils_run_out_%s", Random.rand)
        tmp_err_fname = format("/tmp/vm_utils_run_err_%s", Random.rand)
        shell = "/bin/sh"
        args = format("-c '(%s) > %s 2> %s'", command.gsub("'", %q{\\\'}), tmp_out_fname, tmp_err_fname)
      elsif shell == :cmd
        tmp_out_fname = format('C:\Windows\TEMP\vm_utils_run_out_%s', Random.rand)
        tmp_err_fname = format('C:\Windows\TEMP\vm_utils_run_err_%s', Random.rand)
        shell = "cmd.exe"
        args = format('/c "%s > %s 2> %s"', command.gsub("\"", %q{\\\"}), tmp_out_fname, tmp_err_fname)
      elsif shell == :powershell
        tmp_out_fname = format('C:\Windows\TEMP\vm_utils_run_out_%s', Random.rand)
        tmp_err_fname = format('C:\Windows\TEMP\vm_utils_run_err_%s', Random.rand)
        shell = 'C:\Windows\System32\WindowsPowershell\v1.0\powershell.exe'
        args = format('-Command "%s > %s 2> %s"', command.gsub("\"", %q{\\\"}), tmp_out_fname, tmp_err_fname)
      end

      begin
        exit_code = run_program(shell, args, timeout)
      rescue StandardError
        proc_err = "" # read_file(tmp_err_fname)
        raise format("Error executing command %s. Exit code: %d. StdErr %s", command, exit_code, proc_err)
      end

      read_file(tmp_out_fname)
    end

    def write_file(remote_file, contents)
      # Required privilege: VirtualMachine.GuestOperations.Modify
      put_url = gom.fileManager.InitiateFileTransferToGuest(
        vm: vm,
        auth: guest_auth,
        guestFilePath: remote_file,
        fileAttributes: RbVmomi::VIM::GuestFileAttributes(),
        fileSize: contents.size,
        overwrite: true
      )
      put_url = put_url.gsub(%r{^https://\*:}, format("https://%s:%s", vm._connection.host, put_url))
      uri = URI.parse(put_url)

      request = Net::HTTP::Put.new(uri.request_uri)
      request["Transfer-Encoding"] = "chunked"
      request["Content-Length"] = contents.size
      request.body = contents

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.verify_mode = ssl_verify ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
      http.request(request)
    end

    def read_file(remote_file)
      download_file(remote_file, nil)
    end

    def upload_file(local_file, remote_file)
      Kitchen.logger.debug format("Copy %s to %s", local_file, remote_file)
      write_file(remote_file, File.open(local_file, "rb").read)
    end

    def download_file(remote_file, local_file)
      info = gom.fileManager.InitiateFileTransferFromGuest(vm: vm, auth: guest_auth, guestFilePath: remote_file)
      uri = URI.parse(info.url)

      request = Net::HTTP::Get.new(uri.request_uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.verify_mode = ssl_verify ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
      response = http.request(request)

      if response.body.size != info.size
        raise format("Downloaded file has different size than reported: %s (%d bytes instead of %d bytes)", remote_file, response.body.size, info.size)
      end

      local_file.nil? ? response.body : File.open(local_file, "w") { |file| file.write(response.body) }
    end
  end
end
