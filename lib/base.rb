
require 'logger'

module Base
  attr_accessor :log

  def self.log
    @log ||= init_logger
  end

  def self.init_logger
    log = Logger.new(STDOUT)
    log.progname = 'Knife VCenter'
    log.level = Logger::INFO
    log
  end
end
