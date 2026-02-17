# Windows Subsystem For Linux (WSL) - Alpine

This repository contains a Powershell boostrap script, which automates the installation and configuration of ALpine Linux on WSL.

> [!NOTE]
> WIP: This repository was recently refined and updated.

![Installation complete](/docs/img/alpine-linux.png)

## Features

* **Alpine CDN**: Scrapes the Alpine Linux CDN & downloads the latest minirootfs tarball.
* **Configuration**: Copies local configuration files (`.config/`) to the distro.
* **`OpenRC`**: Configures service runlevels (`sysinit`, `boot`, `default`) for WSL.
* **`cloud-Init`**: Provisions a default or user-defined setup.
* **Interoperability**: Repairs symlinks for WSL tools (`wslpath`, `wslconf`, `wslinfo`).
* **`bash`**: Configures `bash` as the default shell.
* **`git`**: Configures `git` & leverages Windows Git Credential Manager for authentication.
* **`fastfetch`**: Fetches system information and displays it on login, like `neofetch`.

---

> [!WARNING]
> The script requires:
> 1. `Windows 10/11` with `WSL2` enabled
> 2. `PowerShell 5.1`/`PowerShell 7+`
> 3. Administrative privileges

## Quick Start

1. Open a `PowerShell` terminal as **Administrator** and clone this repository.
2. Run the `PowerShell` script - `. .\windows-subsystem-for-linux-alpine\Install-AlpineLinux.ps1`

## Detailed Configuration Steps

There can be some nuance and extra setup involved when manually installing certain distros onto WSL. This is especially true in the case of Alpine linux, which uses the `OpenRC` init system instead of the `Systemd` system and service manager. `Systemd` is fully supported by WSL, whereas `OpenRC` needs manual configuration.

### Alpine Configuration Files

All Linux configuration files and scripts are placed within the `.config` directory and mirror the paths within Alpine.

```
└───.config <- Alpine configuration files
    ├───etc
    │   │   profile   <- Fixed $PATH declaration in minirootfs default profile
    │   │   rc.conf   <- Global OpenRC configuration
    │   │   wsl.conf  <- Default WSL distro configuration
    │   │
    │   ├───apk
    │   │       world <- Required packages for this configuration
    │   │
    │   ├───cloud
    │   │   └───cloud.cfg.d
    │   │           99_wsl.cfg <- cloud-init datasource configuration
    │   │
    │   ├───conf.d
    │   │       syslog <- 128KB buffer in RAM for logs (logread)
    │   │
    │   ├───profile.d
    │   │       colours.sh <- Terminal colour support script
    │   │
    │   └───skel <- Linux 'skeleton' directory
    │       │   .bashrc       <- Environment variables & aliases
    │       │   .bash_logout <- Cleans apk cache & bash history
    │       │   .bash_profile <- Loads `.bashrc` & runs `fastfetch`
    │       │
    │       └───.config
    │           └───git
    │                   config <- Useful default `Git` config
    │
    ├───home
    ├───usr
    │   └───share
    │       └───wsl
    │               
    │
    └───var
        └───lib
            └───cloud
                └───seed
                    └───nocloud
                            meta-data <- NoCloud datasource (default) meta-data
                            user-data <- NoCloud datasource (default) user-data
```

### (1) Environment Validation & Download

The script first checks if the `WslService` is running, enabling it if necessary. It queries the official Alpine Linux CDN to identify the latest available release for version 3.23 (e.g., 3.23.3) and downloads the minirootfs tarball (if not already downloaded). The remote SHA256 hash is compared with the downloaded tarball hash, raising a critical error on mismatch.

### (2) Distribution Import

The downloaded tarball is imported into WSL using `wsl.exe --import`. The default installation path is `%USERPROFILE%\WSL\Alpine`, but this can be customized via the `-InstallDirectory` parameter or when the script  asks for confirmation when ran.

```ps1
. .\windows-subsystem-for-linux-alpine\Install-AlpineLinux.ps1 -InstallDirectory "C:\WSL\Alpine"
```

![install directory](/docs/img/install-directory-check.png)

### (3) Configuration Overlay

The script treats the `.config` directory as the root of the Linux filesystem (/) and recursively copies all  files into the WSL instance.

> [!NOTE]
> The script converts any CRLF line-endings to LF, in case files have been modified on Windows.

### (4) Package Repository Update & Upgrades

The configuration overlay included an `/etc/apk/world` file, which contains each required package. The command `apk update && apk upgrade && apk fix` is executed, which updates apk repositories and upgrades existing packages. The `apk fix` command checks the world file to identify any packages that are missing and require installation.

The Alpine edge community repository is added and tagged with `@edge` - e.g. `apk add fastfetch@edge`.

The default packages in the `world` file:

```sh
alpine-baselayout
alpine-keys
alpine-release
apk-tools
busybox
musl-utils
bash
bash-completion
openrc
mdevd
cloud-init
cloud-init-openrc
util-linux-misc
e2fsprogs-extra
doas
curl
ca-certificates
busybox-openrc
openssh
docs
git
fastfetch@edge
```

> [!NOTE]
> This setup uses `doas` and not `sudo`. Check the `world` file for included packages.

### (5) OpenRC Services & runlevels

Alpine Linux uses the `OpenRC` init system, which is initialised through the configuration overlay `/etc/wsl.conf` file. This distro-level configuration file has `command = "/sbin/openrc default"` under the `[boot]` option, causing `OpenRC` to start correctly.

The script adds required services and respective runlevels:

| Runlevel | Service(s)                                                        |
| -------- | ----------------------------------------------------------------- |
| sysinit  | mdevd, mdevd-init, devfs                                          |
| boot     | bootmisc, machine-id, hostname, hwclock, syslog, cloud-init-local |
| default  | cloud-init, cloud-config, cloud-final, crond, syslog              |

The command `rc-status -a` can be used to view services, status and runlevel configuration.

### (6) Interoperability With WSL Tools

The minirootfs lacks the correct symlinks for WSL integration tools; `wslpath`, `wslconf` and `wslinfo`. The script creates symlinks for these tools, pointing to `/init`. The `wslpath` tool is used to translate between Windows and Linux paths during configuration.

### (7) Interoperability With Git For Windows

On Windows, Git usually sets `credential.helper` to 'manager' which resolves to 'credential-manager' and relates to the Git Credential Manager (GCM) that ships with Git. Typically, `git.exe` is found at `C:\Program Files\Git\cmd` and GCM would therefore be found at `C:\Program Files\Git\mingw64\bin\`.

The script checks to see if Git is installed on Windows and attempts to identify the GCM path. It also checks the `user.name` and `user.email` config values. The skeleton Git config (`/etc/skel/.config/git/config`) is updated with the `user.name` and `user.email` values from Windows Git config (if present) and `credential.helper` is set to the absolute WSL path to the GCM executable on Windows.

This enables GCM to be used to by Git within the Alpine distro. You can still manually create SSH keys or use the `cloud-init` generated SSH keys on GitHub/GitLab etc.

### (8) Terminate Distro

The Alpine distro is terminated ready for a final configuration step with `cloud-init`.

### (9) Cloud-Init Provisioning

[`Cloud-init`](https://cloudinit.readthedocs.io/en/latest/) is the industry standard for customising cross-platform cloud instances. It is most often used by developers, system administrators and other IT professionals to automate configuration of VMs, cloud instances, or machines on a network.

This configuration occurs once, on initial boot - provided `cloud-init` has been installed correctly and the init system (`OpenRC`) is aware of it.

`Cloud-init` has been configured to look for two datasources - `WSL` & `NoCloud`, through a `99_wsl.cfg` config file in `/etc/cloud/cloud.cfg.d/`.

Starting with the `WSL` datasource, `cloud-init` looks for a suitable user-data file in the `%USERPROFILE%\.cloud-init\` directory in the Windows system. If you create a user-data config in that directory, it wil be used in place of the fall-back `NoCloud` setup.

For instructions on how to setup a user-data file for WSL, see the `cloud-init` [documentation](https://cloudinit.readthedocs.io/en/latest/reference/datasources/wsl.html) or [README.md](/%25USERPROFILE%25/.cloud-init/README.md) provided in `%USERPROFILE%/.cloud-init/`.

If a suitable user-data config is not identified, `cloud-init` will use the `NoCloud` datasource config provided by the configuration overlay step. This config file is located at `\var\lib\cloud\seed\nocloud\user-data`.

With the `NoCloud` datasource setup, a default 'alpine' user is created, which is added to `wheel`, `dialout` & `floppy` groups and set as the default user in `/etc/wsl.conf`.

The script waits for `cloud-init` to complete its initial boot setup before continuing.

### (10) update `mdevd` ttyACM Rules

Next, the script fixes the ttyACM rules provided in the default `/etc/mdev.conf`. The `mdevd` package can include Regex rules that use a '+' and do not work as expected. The script replaces 'ttyACM[0-9]+' with 'ttyACM[0-9]*'.

This is done to enable devices such as Raspberry Pi Pico, Arduino Uno (Rev 3+), and many STM32 boards being discovered and added to the correct device node. These devices have firmware that uses Abstract Control Model (ACM) protocol - hence ttyACM[0-9] (native USB). Without this modification, these devices miss the rules and are added to 'floppy' group.

> [!NOTE]
> I might include a default `/etc/mdev.conf` for the bootstrap.

### (11) Terminate Distro

The Alpine distro is terminated once again, and is now ready for use.

### (12) Installation Summary

The script provides a summary table for all configuration files imported into the distro and a `cloud-init` table, showing which datasource was used and any status, errors and the path of a log file.

Example log:

```text
-- Boot Record 01 --
The total time elapsed since completing an event is printed after the "@" character.
The time the event takes is printed after the "+" character.

Starting stage: init-local
|`->no cache found @00.00400s +00.00000s
|`->found local data from DataSourceWSL @00.01000s +00.05000s
Finished stage: (init-local) 00.07200 seconds

Starting stage: init-network
|`->restored from cache with run check: DataSourceWSL @00.35200s +00.00200s
|`->setting up datasource @00.36100s +00.00000s
|`->reading and applying user-data @00.36500s +00.00600s
|`->reading and applying vendor-data @00.37100s +00.00000s
|`->reading and applying vendor-data2 @00.37100s +00.00000s
|`->activating datasource @00.38600s +00.00100s
|`->config-seed_random ran successfully and took 0.000 seconds @00.39900s +00.00000s
|`->config-write_files ran successfully and took 0.000 seconds @00.39900s +00.00100s
|`->config-growpart ran successfully and took 0.003 seconds @00.40000s +00.00300s
|`->config-resizefs ran successfully and took 0.019 seconds @00.40300s +00.01900s
|`->config-mounts ran successfully and took 0.000 seconds @00.42200s +00.00000s
|`->config-set_hostname ran successfully and took 0.002 seconds @00.42200s +00.00200s
|`->config-update_hostname ran successfully and took 0.000 seconds @00.42400s +00.00100s
|`->config-users_groups ran successfully and took 0.030 seconds @00.42500s +00.03000s
|`->config-ssh ran successfully and took 0.007 seconds @00.45500s +00.00600s
|`->config-set_passwords ran successfully and took 0.133 seconds @00.46200s +00.13300s
Finished stage: (init-network) 00.25400 seconds

Starting stage: modules-config
|`->config-ssh_import_id ran successfully and took 0.000 seconds @00.86600s +00.00000s
|`->config-locale ran successfully and took 0.001 seconds @00.86600s +00.00100s
|`->config-runcmd ran successfully and took 0.000 seconds @00.86700s +00.00000s
Finished stage: (modules-config) 00.00800 seconds

Starting stage: modules-final
|`->config-package_update_upgrade_install ran successfully and took 10.194 seconds @01.15400s +10.19400s
|`->config-write_files_deferred ran successfully and took 0.001 seconds @11.34800s +00.00100s
|`->config-scripts_vendor ran successfully and took 0.000 seconds @11.34900s +00.00000s
|`->config-scripts_per_once ran successfully and took 0.000 seconds @11.35000s +00.00000s
|`->config-scripts_per_boot ran successfully and took 0.000 seconds @11.35000s +00.00000s
|`->config-scripts_per_instance ran successfully and took 0.000 seconds @11.35000s +00.00000s
|`->config-scripts_user ran successfully and took 0.002 seconds @11.35100s +00.00100s
|`->config-ssh_authkey_fingerprints ran successfully and took 0.002 seconds @11.35200s +00.00300s
|`->config-keys_to_console ran successfully and took 0.000 seconds @11.35500s +00.00000s
|`->config-install_hotplug ran successfully and took 0.000 seconds @11.35500s +00.00100s
|`->config-final_message ran successfully and took 0.004 seconds @11.35600s +00.00300s
Finished stage: (modules-final) 10.22000 seconds

Total Time: 10.55400 seconds

1 boot records analyzed
```
