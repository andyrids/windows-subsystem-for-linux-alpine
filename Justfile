set shell := ["pwsh.exe", "-NoLogo", "-Command"]

[doc("Shorthand for `just --list`"), default]
_list:
	@just --list

# Elevated privileges check
_isadmin:
	#!pwsh.exe
	$identify = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
	if (-not $identify.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
		Write-Host "Recipe requires Administrator privileges"
		exit 1
	}

# `Get-ExecutionPolicy` check
_isexecution:
	#!pwsh.exe
	$ExecutionPolicy = (Get-ExecutionPolicy).ToString()
	if ($ExecutionPolicy -notin @('RemoteSigned', 'AllSigned', 'Unrestricted')) {
		Write-Host "Execution policy must be 'RemoteSigned', 'AllSigned' or 'Unrestricted'"
		Write-Host "Run ``Set-ExecutionPolicy AllSigned``"
		exit 1
	}

[doc("Run `Install-AlpineLinux.ps1`")]
install: _isadmin _isexecution
	#!pwsh.exe
	. .\Install-AlpineLinux.ps1
