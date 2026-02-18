#!/usr/bin/env pwsh
#requires -RunAsAdministrator
#requires -version 5.1

<#
.SYNOPSIS
    This script bootstraps an Alpine Linux WSL2 distribution with dotfile configuration.

.DESCRIPTION
    This script downloads the latest version of Alpine Linux and bootstraps configuration with files from
    the `.config/` directory. `OpenRC` services are configured and `cloud-init` completes the setup.

.PARAMETER InstallDirectory
    WSL distribution install path. Defaults to `%USERPROFILE%\WSL\Alpine`.

.LINK
    https://github.com/andyrids/windows-subsystem-for-linux-alpine
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$InstallDirectory
)

$Script:ImageImported = $false
$Script:UnicodeSupport = [Console]::OutputEncoding.EncodingName -match "UTF-8" -or $Host.Name -match "Visual Studio Code" -or $PSVersionTable.PSVersion.Major -ge 7

$Script:Theme = @{
    IndentChar  = "  "
    SuccessIcon = if ($UnicodeSupport) { "✔" } else { "[ OK ]" }
    FailIcon    = if ($UnicodeSupport) { "✖" } else { "[FAIL]" }
    WaitSuffix  = "..."
    ColorHeader = "Cyan"
    ColorSuccess= "Green"
    ColorFail   = "Red"
    ColorDim    = "Gray"
}


function Show-Header {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]
        $Title,
        [Parameter(Mandatory=$false)]
        [Int16]
        $Padding=5,
        [Parameter(Mandatory=$false)]
        [switch]
        $Test
    )
    process {
        $Spacing = " ".PadLeft($Padding)
        $DisplayTitle = "$Spacing $($Title.ToUpper()) $Spacing"
        $DisplayTitleBorder = "-".PadLeft($DisplayTitle.Length, "-")

        Write-Host $DisplayTitle -ForegroundColor $Theme.ColorHeader
        Write-Host $DisplayTitleBorder -ForegroundColor White
        Write-Host ""
    }
}


function Get-CursorPosition {
    [CmdletBinding()]
    param()

    process {
        [PSCustomObject]@{ X = [Console]::CursorLeft; Y = [Console]::CursorTop }
    }
}


function Show-TaskProgress {
    [CmdletBinding()]
    param (
        [Parameter(Position=0, Mandatory)]
        [string]
        $TaskName,
        [Parameter(Position=1, Mandatory)]
        [ValidateSet("NONE", "OK", "WARN", "FAIL")]
        [string]
        $TaskResult,
        [Parameter(Position=2, Mandatory=$false)]
        [switch]
        $ToTitleCase
    )

    $TaskNameDisplay = " $TaskName"

    if ($ToTitleCase) {
        $TextInfo = (Get-Culture).TextInfo
        $TaskNameDisplay = $TextInfo.ToTitleCase($TaskNameDisplay)
    }

    function Reset-CursorPosition {
        if ($Host.UI.RawUI.CursorPosition) {
            $Coordinates = New-Object System.Management.Automation.Host.Coordinates(
                0, $Host.UI.RawUI.CursorPosition.Y
            )
            $Host.UI.RawUI.CursorPosition = $Coordinates
        } else {
            # Fallback for ISE/VSCode consoles
            Write-Host "`r" -NoNewline
        }
    }

    $indent = ""

    $Status = switch ($TaskResult) {
        "NONE" { @{ Object = "[....]"; ForegroundColor = "Gray";   NoNewline = $true } }
        "OK"   { @{ Object = "[ OK ]"; ForegroundColor = "Green";  NoNewline = $true } }
        "WARN" { @{ Object = "[WARN]"; ForegroundColor = "Yellow"; NoNewline = $true } }
        "FAIL" { @{ Object = "[FAIL]"; ForegroundColor = "Red";    NoNewline = $true } }
        
    }

    Reset-CursorPosition
    Write-Host ("`r" + $Indent) -NoNewline
    Write-Host @Status
    Write-Host " $TaskNameDisplay" -NoNewline:($TaskResult -eq "NONE")
}


function Show-TaskErrorMessage {
    [CmdletBinding()]
    param (
        [Parameter()]
        [System.Management.Automation.ErrorRecord]
        $ErrorRecord
    )
    Write-Host "`n$($ErrorRecord.Exception.Message)`n" -ForegroundColor Red
}


function Invoke-Task {
    <#
    .SYNOPSIS
        Invokes a series of `ScriptBlock` objects as steps of a task.

    .DESCRIPTION
        This PowerShell function is designed to wrap individual components of the WSL distro configuration.

    .PARAMETER Name
        Name of task.

    .PARAMETER Steps
        Series of `ScriptBlock` objects forming steps of the task.

    .PARAMETER Critical
        A switch causing terminal exit on task failure, if set.

    .EXAMPLE
        Invoke-TerminateDistribution -DistroName "Alpine-3.23.3"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position=0, Mandatory)]
        [string]
        $Name,
        [Parameter(Position=1, Mandatory)]
        [ScriptBlock[]]
        $Steps,
        [Parameter(Position=2, Mandatory=$false)]
        [switch]
        $Critical,
        [Parameter(Position=3, Mandatory=$false)]
        [switch]
        $ToTitleCase
    )

    process {
        Show-TaskProgress -TaskName $Name -TaskResult NONE -ToTitleCase:$ToTitleCase
        try {
            # Run `ScriptBlock` logic within `Steps`
            foreach ($Step in $Steps) { & $Step }
            Show-TaskProgress -TaskName $Name -TaskResult OK -ToTitleCase:$ToTitleCase
        } catch {
            $Result = if ($Critical) { "FAIL" } else { "WARN" }
            Show-TaskProgress -TaskName $Name -TaskResult $Result -ToTitleCase:$ToTitleCase
            Show-TaskErrorMessage -ErrorRecord $_

            if ($Critical) {
                Write-Host " - CRITICAL TASK [ABORT] -`n" -ForegroundColor Red
                if ($VersionString) {
                    Write-Host " - Distro imported [not configured] -`n" -ForegroundColor DarkYellow
                    Write-Host " - ``wsl --list``" -ForegroundColor DarkYellow
                    Write-Host " - ``wsl --unregister <name>```n" -ForegroundColor DarkYellow
                }
                exit 1
            }
        }
    }
}

function Invoke-TerminateDistribution {
    <#
    .SYNOPSIS
        Terminates a specific WSL Linux distro in a structured manner.

    .DESCRIPTION
        This PowerShell function is designed to safely & cleanly shut down a specific WSL instance.

    .PARAMETER DistroName
        Name of the Linux distribution.

    .EXAMPLE
        Invoke-TerminateDistribution -DistroName "Alpine-3.23.3"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position=0, Mandatory)]
        [string]
        $DistroName
    )

    process {
        Invoke-Task -Name "Terminating $DistroName" -Critical -Steps @(
            {
                # Force a sync inside Linux first to flush buffers
                wsl.exe -d $DistroName /bin/sh -c "sync" 
                
                # Wait for Windows host to finalise I/O operations
                Start-Sleep -Seconds 2

                $Log = wsl.exe --terminate $DistroName
                if ($LASTEXITCODE -ne 0) {
                    throw " - Failed to terminate $DistroName - $Log"
                }
            }
        )		
    }
}

# -----------------------------------------------------------------------------
# INITIALISATION
# -----------------------------------------------------------------------------

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$RootPath = if ($PSScriptRoot) { $PSScriptRoot } else { $PWD }
$DEFAULT_WSL_PATH = Join-Path $env:USERPROFILE "WSL" "Alpine"

Clear-Host
Show-Header "ALPINE LINUX BOOTSTRAP"

# -----------------------------------------------------------------------------
# VALIDATE INPUT
# -----------------------------------------------------------------------------

if ([string]::IsNullOrWhiteSpace($InstallDirectory)) {
    $InputPath = Read-Host " - Installation PATH [$DEFAULT_WSL_PATH]"
    
    if ([string]::IsNullOrWhiteSpace($InputPath)) {
        $InstallDirectory = $DEFAULT_WSL_PATH
    } else {
        $InstallDirectory = $InputPath
    }
    Write-Host ""
}

Invoke-Task -Name "Validating installation PATH" -Critical -Steps @(
    {
        $Script:InstallDirectory = [Environment]::ExpandEnvironmentVariables($InstallDirectory)
        $Script:InstallDirectory = $InstallDirectory -replace '"',''
        $Script:InstallDirectory = [System.IO.Path]::GetFullPath($Script:InstallDirectory)

        if (-not (Test-Path -Path $Script:InstallDirectory)) {
            New-Item -ItemType Directory -Path $Script:InstallDirectory -Force | Out-Null
        }

        # Test write access
        $TemporaryFile = Join-Path $Script:InstallDirectory "BOOTSTRAP.tmp"
        New-Item -Path $TemporaryFile -ItemType File -Force | Remove-Item -Force
    }
)

# -----------------------------------------------------------------------------
# WSL SERVICE CHECKS
# -----------------------------------------------------------------------------

Invoke-Task -Name "Checking ``WslService`` status" -Critical -Steps @(
    {
        $WSLService = Get-Service -Name WslService -ErrorAction Stop
        if ($WSLService.StartupType -eq 'Disabled') {
            Set-Service -Name WslService -StartupType Automatic -ErrorAction Stop
        }
    }
)

Invoke-Task -Name "Checking WSL kernel updates" -Steps @(
    {
        # Suppress output unless error
        $UpdateLog = wsl.exe --update 2>&1
        if ($LASTEXITCODE -ne 0) { throw "WSL update failed - $UpdateLog" }
    }
)

# -----------------------------------------------------------------------------
# DOWNLOAD ALPINE LINUX MINIROOTFS
# -----------------------------------------------------------------------------

$ALPINE_VERSION = "latest-stable"
$ALPINE_CDN = "https://dl-cdn.alpinelinux.org/alpine/${ALPINE_VERSION}/releases/x86_64/"
$LatestVersion = $null
$VersionString = $null

Invoke-Task -Name "Fetching Alpine CDN information" -Critical -Steps @(
    {
        $Response = Invoke-WebRequest -Uri $ALPINE_CDN -SkipHttpErrorCheck -UseBasicParsing
        if ($Response.StatusCode -ne 200) { throw "$ALPINE_CDN - HTTP $($Response.StatusCode)" }

        $Versions = $Response.Links |
            Where-Object { $_.href -Like "*minirootfs*tar.gz" } |
            Select-Object -ExpandProperty href -Unique

        $Script:LatestVersion = $Versions | Select-Object -Last 1
        
        $Script:VersionString = $Script:LatestVersion |
            Select-String -Pattern '(\d+\.\d+\.\d+)' | 
            ForEach-Object { $_.Matches.Groups[1].Value }
        
        if (-not $Script:VersionString) { throw "Version parsing error - '$Script:LatestVersion'" }
    }
)

$DistroName = "Alpine-${VersionString}"
$TarFile = Join-Path $RootPath $LatestVersion

if (-not (Test-Path $TarFile)) {

    Invoke-Task -Name "Downloading $LatestVersion" -Critical -Steps @(
        {
            try {
                Invoke-WebRequest -Uri "${ALPINE_CDN}${LatestVersion}" -OutFile $TarFile -UseBasicParsing
            } catch { throw $_ }
        },
        {
            try {
                $CheckSumURL = "${ALPINE_CDN}${LatestVersion}.sha256"
                $CheckSumContent = (Invoke-WebRequest -Uri "$CheckSumURL" -UseBasicParsing).Content

                if ($CheckSumContent -is [byte[]]) {
                    $CheckSumContent = [System.Text.Encoding]::UTF8.GetString($CheckSumContent)
                }

            } catch { throw $_ }

            $RemoteHash = $CheckSumContent.Split(" ")[0].Trim().ToLower()
            $LocalHash = (Get-FileHash -Path $TarFile -Algorithm SHA256).Hash.ToLower()

            if ($RemoteHash -ne $LocalHash) {
                Remove-Item $TarFile -Force
                throw "SHA256 hash ($RemoteHash) mismatch with $TarFile ($LocalHash)"
            }
        }
    )
}

# -----------------------------------------------------------------------------
# IMPORT ALPINE LINUX DISTRO
# -----------------------------------------------------------------------------

$ImageDirectory = $null

Invoke-Task -Name "Importing $LatestVersion" -Critical -Steps @(
    {
        # Check existing distributions
        $DistroList = wsl.exe --list --quiet | ForEach-Object { ($_ -replace "`0", "").Trim() }
        if ($DistroList | Select-String -Pattern $DistroName) {
            throw " - '$DistroName' exists - unregister before reinstall"
        }
        
        # All WSL images are named `ext4.vhdx`, so we place them in $InstallDirectory\$DistroName DIR
        $Script:ImageDirectory = New-Item -Path $InstallDirectory -Name $DistroName -ItemType "Directory" |
            Select-Object -ExpandProperty FullName

        $ImportLog = wsl.exe --import $DistroName $ImageDirectory $TarFile 2>&1
        if ($LASTEXITCODE -ne 0) { throw " - WSL import failed - $ImportLog" }
        # Allow Windows to finalize the VHDX handle
        Start-Sleep -Seconds 3

        $Script:ImageImported = $true
    }
)

# -----------------------------------------------------------------------------
# CONFIGURATION BOOTSTRAP
# -----------------------------------------------------------------------------

# Configuration information
$ConfigReport = [System.Collections.Generic.List[PSObject]]::new()

Invoke-Task -Name "Importing bootstrap files" -Critical -Steps @(
    {
        wsl.exe -d $DistroName echo "INIT" | Out-Null;

        # Helper to resolve WSL path
        $WSLRoot = wsl.exe -d $DistroName wslpath -w /
        $DotConfigPath = Join-Path $RootPath ".config"

        if (Test-Path $DotConfigPath) {
            $Files = Get-ChildItem $DotConfigPath -Recurse -File

            $i = 0
            foreach ($File in $Files) {
                $i++
                Write-Progress -Activity "Copying files" -Status $File.Name -PercentComplete (($i / $Files.Count) * 100)

                $RelativeFullName = $File.FullName -replace "^$([regex]::Escape($DotConfigPath))"
                $LinuxFullName = Join-Path $WSLRoot $RelativeFullName
                $LinuxParent = Split-Path $LinuxFullName -Parent

                $Action = "Imported (LF)"

                if (-not (Test-Path $LinuxParent)) {
                    New-Item -Path $LinuxParent -ItemType Directory -Force | Out-Null
                }

                # Normalise CRLF -> LF
                $IsBinary = $false
                $Extension = [System.IO.Path]::GetExtension($File.Name).ToLower()
                $BinaryExtensions = @(".gz", ".tar", ".png", ".bin", ".iso", ".7z")

                if ($BinaryExtensions -contains $Extension) {
                    $IsBinary = $true
                } else {
                    # Read bytes to check for NULL values
                    try {
                        $Bytes = [System.IO.File]::ReadAllBytes($File.FullName)
                        $ScanLength = [Math]::Min($Bytes.Length, 4096)
                        for ($k = 0; $k -lt $ScanLength; $k++) {
                            if ($Bytes[$k] -eq 0) {
                                $IsBinary = $true
                                break
                            }
                        }
                    } catch {
                        # Fallback to safer binary copy
                        $IsBinary = $true
                    }
                }

                if ($IsBinary) {
                    Copy-Item -Path $File.FullName -Destination $LinuxFullName -Force
                } else {
                    # CRLF -> LF
                    try {
                        $Content = [System.Text.Encoding]::UTF8.GetString($Bytes)

                        if ($Content -match "`r`n") {
                            $Content = $Content -replace "`r`n", "`n"

                            # UTF8 No BOM
                            $UTF8NoBOM = New-Object System.Text.UTF8Encoding($false)
                            [System.IO.File]::WriteAllText($LinuxFullName, $Content, $UTF8NoBOM)

                            $Action = "Imported (CRLF -> LF)"
                        } else {
                            Copy-Item -Path $File.FullName -Destination $LinuxFullName -Force
                        }
                    } catch {
                        Copy-Item -Path $File.FullName -Destination $LinuxFullName -Force
                    }
                }

                # Add to `ConfigReport`
                $ConfigReport.Add([PSCustomObject]@{
                    File   = $RelativeFullName
                    Target = "/$($RelativeFullName.TrimStart('\').Replace('\','/'))"
                    Action = $Action
                })
            }
            Write-Progress -Activity "Copying files" -Completed
        }
    }
)

# -----------------------------------------------------------------------------
# UPDATE & UPGRADE PACKAGES
# -----------------------------------------------------------------------------

# world: util-linux-misc -> util-linux

Invoke-Task -Name "Updating indexes & upgrading" -Critical -Steps @(
    {
        # Add edge community repository tagged with `@edge` - e.g. `apk add fastfetch@edge`
        $EdgeRepository = "https://dl-cdn.alpinelinux.org/alpine/edge/community"
        $ApkRepositories = "/etc/apk/repositories"
        $Log = wsl.exe -d $DistroName /bin/sh -c "echo '@edge $EdgeRepository' >> $ApkRepositories" 2>&1

        if ($LASTEXITCODE -ne 0) { throw " - Failed to update $ApkRepositories - $Log" }

        # `apk fix` installs missing packages from `/etc/apk/world`
        $Log = wsl.exe -d $DistroName /bin/sh -c "apk update && apk upgrade && apk fix" 2>&1

        if ($LASTEXITCODE -ne 0) { throw " - $Log" }		
    }
)
# -----------------------------------------------------------------------------
# CONFIGURE OPEN-RC SERVICES & RUNLEVELS
# -----------------------------------------------------------------------------

Invoke-Task -Name "Configuring service runlevels" -Critical -Steps @(
    {
        <#
        Services & target runlevels

        TODO: Identify & remove any unneeded services

        sysinit: removed `hwdrivers` & `dmesg`
        #>

        $Services = [ordered]@{
            "sysinit" = @("mdevd", "mdevd-init", "devfs")
            "boot"    = @("bootmisc", "machine-id", "hostname", "hwclock", "syslog", "cloud-init-local")
            "default" = @("cloud-init", "cloud-config", "cloud-final", "crond")
        }

        $CommandList = [System.Collections.Generic.List[string]]::new()

        foreach ($Level in $Services.Keys) {
            foreach ($Service in $Services[$Level]) {
                $CommandList.Add("rc-update add $Service $Level 2>/dev/null || true")
            }
        }

        if ($CommandList.Count -gt 0) {
            $LinuxCmd = $CommandList -join " && "
            $Log = wsl.exe -d $DistroName /bin/sh -c "$LinuxCmd" 2>&1

            if ($LASTEXITCODE -ne 0) { throw " - Failed to add services to runlevels - $Log" }
        }
    }
)

# -----------------------------------------------------------------------------
# CONFIGURE INTEROP SYMLINKS; `wslpath`, `wslconf` & `wslinfo`
# -----------------------------------------------------------------------------

Invoke-Task -Name "Fixing WSL tool symlinks" -Critical -Steps @(
    {
        $CommandList = [System.Collections.Generic.List[string]]::new()
        foreach ($Tool in @("wslpath", "wslconf", "wslinfo")) {
            $CommandList.Add("ln -sf /init /usr/bin/$Tool")
        }

        $LinuxCmd = $CommandList -join " && "
        $Log = wsl.exe -d $DistroName /bin/sh -c "$LinuxCmd" 2>&1

        if ($LASTEXITCODE -ne 0) { throw "Failed to create symbolic links for WSL tools - $Log" }
    }
)

# -----------------------------------------------------------------------------
# CONFIGURE WINDOWS GIT INTEROP
# -----------------------------------------------------------------------------

Invoke-Task -Name "Updating Git config" -Steps @(
    {
        try {
            $GitCmdPath = (Get-Command git -ErrorAction Stop).Source
        }
        catch { throw "Git is not installed - ``winget install --id Git.Git -e --source winget``" }

        <#
        On Windows, Git usually sets `credential.helper` to 'manager' which resolves to 'credential-manager' and
        relates to the Git Credential Manager (GCM) that ships with Git.

        As an example, `git.exe` is typically @ `C:\Program Files\Git\cmd` and GCM would therefore be
        found at `C:\Program Files\Git\mingw64\bin\`.
        #>

        $Log = git credential-manager --version
        if ($LASTEXITCODE -ne 0) { throw "Git Credential Manager is not installed - $Log" }

        $GitBasePath = $GitCmdPath | Split-Path -Parent | Split-Path -Parent
        $GCMPath = Join-Path -Path $GitBasePath -ChildPath "mingw64\bin\git-credential-manager.exe"

        if (Test-Path -Path $GCMPath -PathType Leaf) {
            # $GCMLinuxPath = wsl.exe -d $DistroName wslpath -u "$GCMPath"
            # $GCMLinuxPath = wsl.exe -d $DistroName /bin/bash -c "printf '%q' '$GCMLinuxPath'"
            $GCMLinuxPath = wsl.exe -d $DistroName /bin/bash -c "printf '%q' `"`$(wslpath -u '$GCMPath')`""

            # Update skeleton config for all users
            $ConfigFile = "/etc/skel/.config/git/config"

            $Log = wsl.exe -d $DistroName git config set -f "$ConfigFile" credential.helper "$GCMLinuxPath"
            if ($LASTEXITCODE -ne 0) { throw "Error setting Git credential.helper - $Log" }
        } else { throw "Git Credential Manager not found @ '$GCMPath'" }

        $GitUserName = git config get user.name
        $GitUserEmail = git config get user.email

        if  (-not ($GitUserName -and $GitUserEmail)) {
            throw "user.name & user.email are unset in Windows Git config"
        }

        $Log = wsl.exe -d $DistroName git config set -f "$ConfigFile" user.name "$GitUserName"
        if ($LASTEXITCODE -ne 0) { throw "Error setting Git user.name - $Log" }

        $Log = wsl.exe -d $DistroName git config set -f "$ConfigFile" user.email "$GitUserEmail"
        if ($LASTEXITCODE -ne 0) { throw "Error setting Git user.email - $Log" }
    }
)

# -----------------------------------------------------------------------------
# MODIFY MDEVD ttyACM RULES
# -----------------------------------------------------------------------------

Invoke-Task -Name "Fixing mdevd ttyACM rules" -Steps @(
    {
        $CommandList = [System.Collections.Generic.List[string]]::new()
        foreach ($Device in @("ttyACM", "ttyUSB")) {
            $CommandList.Add("sed -i 's/$Device\[0-9\]+/$Device\[0-9\]*/g' /etc/mdev.conf")
        }

        # Replace 'ttyACM[0-9]+' with 'ttyACM[0-9]*'
        $LinuxCmd = $CommandList -join " && "
        $Log = wsl.exe -d $DistroName /bin/sh -c "$LinuxCmd" 2>&1

        if ($LASTEXITCODE -eq 1) { throw " - Failed to update mdev rules - $Log" }
    }
)

# -----------------------------------------------------------------------------
# TERMINATE DISTRO
# -----------------------------------------------------------------------------

Invoke-TerminateDistribution -DistroName $DistroName

# -----------------------------------------------------------------------------
# CLOUD-INIT DISTRO INITIALISATION
# -----------------------------------------------------------------------------

$CIReport = [PSCustomObject]@{
    "Datasource" = $null
    "Status" = $null
    "Extended Status" = $null
    "Recoverable Errors" = $null
    "Log" = $null
}

Invoke-Task -Name "Awaiting cloud-init first-boot" -Critical -Steps @(
    {
        # Restart distribution
        wsl.exe -d $DistroName echo "INIT" | Out-Null;

        # Wait for `cloud-init` to finish configuration
        $Log = wsl.exe -d $DistroName cloud-init status --wait --long --format json 2>&1

        if ($LASTEXITCODE -eq 1) { throw " - cloud-init critical error" }

        $Status = $Log | Out-String | ConvertFrom-Json

        # `Join-String` was introduced PowerShell 6.1
        $RecoverableErrors = ($Status.recoverable_errors.ERROR | Select-Object -Unique) -join "`r`n"
        
        if ([string]::IsNullOrWhiteSpace($RecoverableErrors)) {
            $RecoverableErrors = "N/A"
        }

        $DateTime = (Get-Date).ToString('yyyyMMdd-hhmm')
        $ShowPathWin = Join-Path -Path $RootPath -ChildPath "$DateTime-cloud-init.log"
        # Wrap the path in single quotes for literal '\' in Linux
        $ShowReport = wsl.exe -d $DistroName wslpath -u "'$ShowPathWin'"
        wsl.exe -d $DistroName cloud-init analyze show --outfile $ShowReport 2>&1

        $TextInfo = (Get-Culture).TextInfo

        $CIReport."Datasource" = $Status.detail
        $CIReport."Status" = $TextInfo.ToTitleCase($Status.status)
        $CIReport."Extended Status" = $TextInfo.ToTitleCase($Status.extended_status)
        $CIReport."Recoverable Errors" = $RecoverableErrors
        $CIReport."Log" = $ShowPathWin
    }
)

# -----------------------------------------------------------------------------
# TERMINATE DISTRO
# -----------------------------------------------------------------------------

Invoke-TerminateDistribution -DistroName $DistroName

# -----------------------------------------------------------------------------
# SUMMARY
# -----------------------------------------------------------------------------

Write-Host "`n- INSTALLATION COMPLETE -`n" -ForegroundColor Green

if ($ConfigReport.Count -gt 0) {
    $TableBootstrap = $ConfigReport |
        Format-Table -AutoSize |
        Out-String -Stream | 
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    
    Write-Host $TableBootstrap[0] -ForegroundColor DarkGreen
    Write-Host $TableBootstrap[1] -ForegroundColor White

    for ($i = 2; $i -lt $TableBootstrap.Count; $i++) {
        Write-Host $TableBootstrap[$i] -ForegroundColor Gray
    }

    Write-Host ""

    $TableCloudInit = $CIReport |
        Format-Table -AutoSize |
        Out-String -Stream | 
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    
    Write-Host $TableCloudInit[0] -ForegroundColor DarkGreen
    Write-Host $TableCloudInit[1] -ForegroundColor White

    for ($i = 2; $i -lt $TableCloudInit.Count; $i++) {
        Write-Host $TableCloudInit[$i] -ForegroundColor Gray
    }
}

Write-Host "`n- Run distribution: wsl -d $DistroName -`n" -ForegroundColor Green

# rc-status -a

# cloud-init status --wait
# cloud-init status --long
# doas cloud-init status -l -w --format yaml
# id alpine2
# cloud-id

# cat /etc/doas.conf 
# cat /etc/passwd
# cat /etc/wsl.conf
# echo $0

# cloud-init analyze blame
# cloud-init analyze show

# logread

# cloud-init schema --system --annotate
# cloud-init clean --logs --reboot

# wsl.exe -d Alpine-3.23.3 /bin/sh -c "wslpath -u 'C:\Program Files\Git\mingw64\bin\git-credential-manager.exe'
# $command = "printf %q '$GCM'"

# $gcmPath = "${env:ProgramFiles}\Git\mingw64\bin\git-credential-manager.exe"
# if (Test-Path $gcmPath) { Split-Path $gcmPath }

# Get-ChildItem -Path "C:\Program Files\Git" -Filter "git-credential-manager.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -ExpandProperty DirectoryName
# New-Item -Path ".\" -Name "Logfiles" -ItemType "Directory" | Select-Object -ExpandProperty FullName