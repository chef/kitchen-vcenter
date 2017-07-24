# kitchen-vcenter

## Usage

In the `.kitchen.yml` file

```yml
driver:
  name: vcenter
```

### Required parameters:

The following parameters should be set in the main `driver_config` section as they are common to all platforms.

 - `vcenter_username` - Name to use when connecting to the vSphere environment
 - `vcenter_password` - Password associated with the specified user
 - `vcenter_host` - Host against which logins should be attempted
 - `vcenter_disable_ssl_verify` - Whether or not to disable SSL verification checks. Good when using self signed certificates. Default: false

The following parameters should be set in the `driver_config` for the individual platform.

 - `targethost` - Host on which the new virtual machine should be created
 - `template` - Template or virtual machine to use when cloning the new machine
 - `datacenter` - Name of the datacenter to use to deploy into

### Optional Parameters

The following optional parameters should be used in the `driver_config` for the platform.

 - `folder` - Folder into which the new machine should be stored. If specified the folder _must_ already exist
