#-------------------------------------------------------------------------------------
# <copyright file="AzureServiceDeployClient.ps1" company="Microsoft">
#     Copyright (c) Microsoft Corporation.  All rights reserved.
# </copyright>
#
# <Summary>
#     AzureServiceDeploy Powershell command console startup script.
# </Summary>
#-------------------------------------------------------------------------------------
param(
    [bool]$fromShortcut,
    [bool]$skipScriptUpdate
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ev2NugetSource = "https://msazure.pkgs.visualstudio.com/_packaging/ExpressV2/nuget/v3/index.json"

$startupScriptPkgName = "Microsoft.Azure.AzureServiceDeployClientStartup"
$sdkPackageName = "Microsoft.Azure.AzureServiceDeployClient"

function CheckScriptUpdate
{
    try
    {
        $scriptPackagePath = Join-Path $azureServiceDeployClientPath "AzureServiceDeployClientStartup"
        $startupPkgVersionFile = Join-Path $azureServiceDeployClientPath "AzureServiceDeployClientStartup_version.txt"
        $found = $false

        EnsureDependencyPresence

        # Query latest version and check with the current version of the startup script.
        $latestPkgVer = GetLatestPackageVersion $startupScriptPkgName $ev2NugetSource

        if (Test-Path $startupPkgVersionFile)
        {
            $installedVersion = Get-Content $startupPkgVersionFile
            $found = $installedVersion -eq $latestPkgVer
        }

        if (!$found)
        {
            Write-Host "Latest startup script not found. Downloading latest startup package $startupScriptPkgName."
            DownloadStartupScriptPackage $scriptPackagePath $latestPkgVer

            $scriptPackageLibPath = "$scriptPackagePath\$startupScriptPkgName.$latestPkgVer\lib\"

            # Update nuget.exe and credential provider exe from startup package path to the Startup-Script path
            $newNugetExePath = Join-Path $scriptPackageLibPath "Nuget.exe"
            if (Test-Path $newNugetExePath) {
                xcopy $newNugetExePath, $scriptPath /Y /C | Out-Null
            }

            $newCredManagerPath = Join-Path $scriptPackageLibPath "CredentialProvider.VSS.exe"
            if (Test-Path $newCredManagerPath) {
                xcopy $newCredManagerPath, $scriptPath /Y /C | Out-Null
            }

            $clientStartupPath = Join-Path $scriptPackageLibPath "AzureServiceDeployClient.ps1"
            if (Test-Path $clientStartupPath) {
                xcopy $clientStartupPath $scriptPath /Y /C | Out-Null

                Set-Content -Path $startupPkgVersionFile $latestPkgVer

                # Remove AzureServiceDeployClientStartup directory in %localappdata%
                Remove-Item $scriptPackagePath -Force -Recurse -Confirm:$false

                . "$scriptPath\AzureServiceDeployClient.ps1"

                return
            }
        }
    }
    catch
    {
        Write-Warning "Failed to update current script, continue to run the existing one"
    }

    if (Test-Path $scriptPackagePath)
    {
        Remove-Item $scriptPackagePath -Force -Recurse -Confirm:$false
    }

    LaunchCmdlet
}

function EnsureDependencyPresence
{
    if (!(Test-Path $nugetPath))
    {
        $appLocalNugetPath = Join-Path $azureServiceDeployClientPath "nuget.exe" 
        if (Test-Path $appLocalNugetPath)
        {
            xcopy $appLocalNugetPath, $scriptPath /Y /C | Out-Null
        }
        else {
            Write-Host "Required dependencies not found. Copy the latest Ev2 cmdlets and try again."
        }
    }

    $credManagerPath = Join-Path $scriptPath "CredentialProvider.VSS.exe"
    if (!(Test-Path $credManagerPath))
    {
        $appLocalCredMgrPath = Join-Path $azureServiceDeployClientPath "CredentialProvider.VSS.exe"
        if (Test-Path $appLocalCredMgrPath)
        {
            xcopy $appLocalCredMgrPath, $scriptPath /Y /C | Out-Null
        }
        else {
            Write-Host "Required dependencies not found. Copy the latest Ev2 cmdlets and try again."
        }
    }
}

function DownloadStartupScriptPackage($scriptPackagePath, $latestPkgVer)
{
    # Recreate AzureServiceDeployClientStartup directory before downloading the latest client startup package to that dir.
    if (Test-Path $scriptPackagePath)
    {
        Remove-Item -Path $scriptPackagePath -Force -Recurse -Confirm:$false
    }

    New-Item -ItemType Directory $scriptPackagePath | Out-Null
    & $nugetPath install $startupScriptPkgName -Prerelease -version $latestPkgVer -o $scriptPackagePath -ConfigFile "$azureServiceDeployClientPath\Nuget.config"
}

function write-header 
{
    param ([string]$s)
    $greeting = "`n*** $s ***`n"
    return $greeting
}

function SetupUI 
{
    write-host "Windows PowerShell"
    write-host "Copyright (C) 2020 Microsoft Corporation. All rights reserved."
    write-host 
    # available: "Black, DarkBlue, DarkGreen, DarkCyan, DarkRed, DarkMagenta, DarkYellow, Gray, DarkGray, Blue, Green, Cyan, Red, Magenta, Yellow, White
    $title = "Azure Service Deploy PowerShell"
    try
    {
        $Host.UI.RawUI.WindowTitle = $title
    }
    catch
    {
        # ignore error when Core language is not allowed in SAW machine
    }
    $msg = write-header "Welcome to $title"
    write-host $msg -foregroundcolor Cyan
}

function InstallLatestVersion($targetPath, $lastestPkg)
{
    if (!(Test-Path $targetPath))
    {
        New-Item -ItemType Directory $targetPath | Out-Null
    }

    $asdc = Join-Path $targetPath $lastestPkg 

    Write-Host "Fetching latest version $latestVStr of $sdkPackageName package"
    
    & $nugetPath install $sdkPackageName -Prerelease -version $latestVStr -o $targetPath -ConfigFile "$azureServiceDeployClientPath\Nuget.config"
    if (!(Test-Path "$targetPath\Microsoft.IdentityModel.Clients.ActiveDirectory.5.2.4"))
    {
        Remove-Item -Path "$targetPath\Microsoft.IdentityModel.Clients.ActiveDirectory*" -Force -Recurse -Confirm:$false
        & $nugetPath install "Microsoft.IdentityModel.Clients.ActiveDirectory" -version "5.2.4" -o $targetPath -ConfigFile "$azureServiceDeployClientPath\Nuget.config"
    }
    if (!(Test-Path "$targetPath\Newtonsoft.Json.9.0.1"))
    {
        Remove-Item -Path "$targetPath\Newtonsoft.Json*" -Force -Recurse -Confirm:$false
        & $nugetPath install "Newtonsoft.Json" -version "9.0.1" -o $targetPath -ConfigFile "$azureServiceDeployClientPath\Nuget.config"
    }
    xcopy "$asdc\lib\*.*" $targetPath /Y /C | Out-Null
    $manifest = "$targetPath\AzureServiceDeployClient.manifest"
    if (Test-Path $manifest)
    {
        Get-Content $manifest | % {
            $parts = $_.Split(',');
            $path = (Get-ChildItem -Directory "$targetPath\$($parts[0]).*")[0].Name;
            xcopy "$targetPath\$path\$($parts[1])\*.*" $targetPath /Y /C | Out-Null
        }
    }
    else
    {
        # fallback when there is no manifest file in the package
        $path = (Get-ChildItem -Directory "$targetPath\Microsoft.IdentityModel.Clients.ActiveDirectory.*")[0].Name
        xcopy "$targetPath\$path\lib\net45\*.*" $targetPath /Y /C
        $path = (Get-ChildItem -Directory "$targetPath\WindowsAzure.Storage.*")[0].Name
        xcopy "$targetPath\$path\lib\net40\*.*" $targetPath /Y /C
        $path = (Get-ChildItem -Directory "$targetPath\Newtonsoft.Json.*")[0].Name
        xcopy "$targetPath\$path\lib\net40\*.*" $targetPath /Y /C
        $path = (Get-ChildItem -Directory "$targetPath\Microsoft.AspNet.WebApi.Client.*")[0].Name
        xcopy "$targetPath\$path\lib\net45\*.*" $targetPath /Y /C
        $path = (Get-ChildItem -Directory "$targetPath\Microsoft.AspNet.WebApi.Core.*")[0].Name
        xcopy "$targetPath\$path\lib\net45\*.*" $targetPath /Y /C
        $path = (Get-ChildItem -Directory "$targetPath\System.IdentityModel.Tokens.Jwt.*")[0].Name
        xcopy "$targetPath\$path\lib\net45\*.*" $targetPath /Y /C
        $path = (Get-ChildItem -Directory "$targetPath\System.ValueTuple.*")[0].Name
        xcopy "$targetPath\$path\lib\netstandard1.0\*.*" $targetPath /Y /C
    }

    Get-ChildItem -Directory -Exclude CmdLets,Samples,Schema $targetPath | %{ Remove-Item $_ -Force -Recurse -Confirm:$false }
}

function SetupNugetConfigFile
{
    $config = '<?xml version="1.0" encoding="utf-8"?>' +
        '<configuration>' +
            '<packageSources>' +
                '<add key="ExpressV2" value="{0}" />' +
            '</packageSources>' + 
            '<activePackageSource>' +
                '<add key="ExpressV2" value="{0}" />' +
            '</activePackageSource>' +
        '</configuration>'
    $config -f $ev2NugetSource | Out-File "$azureServiceDeployClientPath\Nuget.config" -Encoding ascii
}

function GetLatestPackageVersion($packageName, $source)
{
    $configFilePath = "$azureServiceDeployClientPath\Nuget.config"

    $packages = & $nugetPath list $packageName -Prerelease -Source $source -ConfigFile $configFilePath
    if (!($packages) -or ($packages -contains "No packages found.")) {
        # if no package found in the mirror source then throw
        throw
    }
  
    $versions = @()
    $vStrs = @()
    # Parsing all version string to version oject and get the latest
    foreach ($p in $packages) {
        if ($p.Contains($packageName)) {
            $vStr = $p.Split(' ')[1]
            $vStrs = $vStrs + $vStr
            $v = new-object Version($vstr.Split('-')[0])
            $versions = $versions + $v
        }
    }
    $latestVersion = ($versions | Sort -Descending)[0].ToString()
    $latestVStr = $vStrs | ? { $_.Contains($latestVersion) }

    return $latestVStr
}

function LaunchCmdlet
{
    try
    {
        # Check if any previous version already installed
        $versionFile = Join-Path $azureServiceDeployClientPath "versions.txt"
        $InstalledVersions = $null
        $prevVersion = $null
        $found = $false
        $latestVstr = $null
        if (Test-Path $versionFile)
        {
            $InstalledVersions = Get-Content $versionFile
            if ($InstalledVersions)
            {
                if ($InstalledVersions.GetType().Name -ieq "String")
                {
                    $prevVersion = $InstalledVersions
                }
                else
                {
                    $prevVersion = $InstalledVersions[$InstalledVersions.Length - 1]
                }
            }
        }

        # Ensuring dependency presence of nuget.exe and Cred Provider for back-compat
        EnsureDependencyPresence

        Write-Host "Checking for latest version of Azure Service Deploy cmdlets"
        # Query latest version

        $latestVstr = GetLatestPackageVersion $sdkPackageName $ev2NugetSource
        $lastestPkg = "$sdkPackageName.$latestVStr"
        if ($InstalledVersions)
        {
            $found = $InstalledVersions | ? { $_ -eq $latestVStr }    
        }

        if (!$found)
        {
            if ($prevVersion)
            {
                # try to delete all older version except n-1
                Get-ChildItem -Directory -Exclude $prevVersion $azureServiceDeployClientPath | %{ Remove-Item $_ -Force -Recurse -Confirm:$false -ErrorAction SilentlyContinue | Out-Null }
            }

            InstallLatestVersion -targetPath "$azureServiceDeployClientPath\$latestVStr" -lastestPkg $lastestPkg
            Set-Content -Path $versionFile $prevVersion
            Add-Content -Path $versionFile $latestVstr
            $scriptPath = Join-Path $azureServiceDeployClientPath $latestVstr
        }
        else
        {
            $scriptPath = Join-Path $azureServiceDeployClientPath $prevVersion
            $latestVStr = $prevVersion
        }

        cls
    }
    catch
    {
        if ($latestVstr)
        {
            Remove-Item (Join-Path $azureServiceDeployClientPath $latestVstr) -Force -Recurse -Confirm:$false
        }

        if ($prevVersion)
        {
            $scriptPath = Join-Path $azureServiceDeployClientPath $prevVersion
            $latestVStr = $prevVersion
        }
        else
        {
            Write-Error "Cannot access Nuget source to install the cmdlets at this time. Cannot fall back to a previously installed version either since none was found."
            Write-Warning "Please check network and try again."
            return
        }

        cls
        Write-Warning "Not able to fetch latest version of Azure Service Deploy cmdlets package"
        Write-Warning "Will continue to start with currently installed version of cmdlets if present."
    }

    SetupUI

    Write-Host "Using version $latestVStr"
    Write-Host "Load module from $scriptPath"

    $modulesToImport = @("Microsoft.Azure.Deployment.Express.Client" )

    foreach ($e in $modulesToImport) {
      Import-Module -global (Join-Path $scriptPath "$e.dll")
    }

    $cmdlets = $modulesToImport | %{ Get-Command -Module $_ } | %{$_.Name}
    $commands = ($cmdlets | Select -Unique | Sort)

    # Display the available cmdlets
    write-host "`n Commands:" -foregroundcolor Cyan
    $commands | %{write-host (' * {0}' -f $_) -foregroundcolor Cyan}

    write-Host
    write-host "For help on commands type Get-Help <command name>" -foregroundcolor Cyan
    write-Host

    try
    {
        $fileVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo("$scriptPath\Microsoft.Azure.Deployment.Express.Client.dll").FileVersion
        $Host.UI.RawUI.WindowTitle += " $fileVersion ($latestVStr)"
    }
    catch
    {
        # ignore error when Core language is not allowed in SAW machine
    }
}

$scriptPath = Split-Path -Parent $PSCommandPath
$nugetPath = Join-Path $scriptPath "nuget.exe"
$azureServiceDeployClientPath = Join-Path $env:LOCALAPPDATA "Microsoft\AzureServiceDeployClient"

if (!(Test-Path $azureServiceDeployClientPath))
{
    New-Item -ItemType Directory $azureServiceDeployClientPath | Out-Null
}

SetupNugetConfigFile

if ($skipScriptUpdate)
{
    LaunchCmdlet
}
else
{
    CheckScriptUpdate
}

# SIG # Begin signature block
# MIIjhQYJKoZIhvcNAQcCoIIjdjCCI3ICAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCC+PRGd0De8NcTC
# mqluIaaM8Nt8vRPmQYVP+V84E1/lnqCCDYEwggX/MIID56ADAgECAhMzAAAB32vw
# LpKnSrTQAAAAAAHfMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjAxMjE1MjEzMTQ1WhcNMjExMjAyMjEzMTQ1WjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQC2uxlZEACjqfHkuFyoCwfL25ofI9DZWKt4wEj3JBQ48GPt1UsDv834CcoUUPMn
# s/6CtPoaQ4Thy/kbOOg/zJAnrJeiMQqRe2Lsdb/NSI2gXXX9lad1/yPUDOXo4GNw
# PjXq1JZi+HZV91bUr6ZjzePj1g+bepsqd/HC1XScj0fT3aAxLRykJSzExEBmU9eS
# yuOwUuq+CriudQtWGMdJU650v/KmzfM46Y6lo/MCnnpvz3zEL7PMdUdwqj/nYhGG
# 3UVILxX7tAdMbz7LN+6WOIpT1A41rwaoOVnv+8Ua94HwhjZmu1S73yeV7RZZNxoh
# EegJi9YYssXa7UZUUkCCA+KnAgMBAAGjggF+MIIBejAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUOPbML8IdkNGtCfMmVPtvI6VZ8+Mw
# UAYDVR0RBEkwR6RFMEMxKTAnBgNVBAsTIE1pY3Jvc29mdCBPcGVyYXRpb25zIFB1
# ZXJ0byBSaWNvMRYwFAYDVQQFEw0yMzAwMTIrNDYzMDA5MB8GA1UdIwQYMBaAFEhu
# ZOVQBdOCqhc3NyK1bajKdQKVMFQGA1UdHwRNMEswSaBHoEWGQ2h0dHA6Ly93d3cu
# bWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY0NvZFNpZ1BDQTIwMTFfMjAxMS0w
# Ny0wOC5jcmwwYQYIKwYBBQUHAQEEVTBTMFEGCCsGAQUFBzAChkVodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY0NvZFNpZ1BDQTIwMTFfMjAx
# MS0wNy0wOC5jcnQwDAYDVR0TAQH/BAIwADANBgkqhkiG9w0BAQsFAAOCAgEAnnqH
# tDyYUFaVAkvAK0eqq6nhoL95SZQu3RnpZ7tdQ89QR3++7A+4hrr7V4xxmkB5BObS
# 0YK+MALE02atjwWgPdpYQ68WdLGroJZHkbZdgERG+7tETFl3aKF4KpoSaGOskZXp
# TPnCaMo2PXoAMVMGpsQEQswimZq3IQ3nRQfBlJ0PoMMcN/+Pks8ZTL1BoPYsJpok
# t6cql59q6CypZYIwgyJ892HpttybHKg1ZtQLUlSXccRMlugPgEcNZJagPEgPYni4
# b11snjRAgf0dyQ0zI9aLXqTxWUU5pCIFiPT0b2wsxzRqCtyGqpkGM8P9GazO8eao
# mVItCYBcJSByBx/pS0cSYwBBHAZxJODUqxSXoSGDvmTfqUJXntnWkL4okok1FiCD
# Z4jpyXOQunb6egIXvkgQ7jb2uO26Ow0m8RwleDvhOMrnHsupiOPbozKroSa6paFt
# VSh89abUSooR8QdZciemmoFhcWkEwFg4spzvYNP4nIs193261WyTaRMZoceGun7G
# CT2Rl653uUj+F+g94c63AhzSq4khdL4HlFIP2ePv29smfUnHtGq6yYFDLnT0q/Y+
# Di3jwloF8EWkkHRtSuXlFUbTmwr/lDDgbpZiKhLS7CBTDj32I0L5i532+uHczw82
# oZDmYmYmIUSMbZOgS65h797rj5JJ6OkeEUJoAVwwggd6MIIFYqADAgECAgphDpDS
# AAAAAAADMA0GCSqGSIb3DQEBCwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0
# ZSBBdXRob3JpdHkgMjAxMTAeFw0xMTA3MDgyMDU5MDlaFw0yNjA3MDgyMTA5MDla
# MH4xCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMT
# H01pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTEwggIiMA0GCSqGSIb3DQEB
# AQUAA4ICDwAwggIKAoICAQCr8PpyEBwurdhuqoIQTTS68rZYIZ9CGypr6VpQqrgG
# OBoESbp/wwwe3TdrxhLYC/A4wpkGsMg51QEUMULTiQ15ZId+lGAkbK+eSZzpaF7S
# 35tTsgosw6/ZqSuuegmv15ZZymAaBelmdugyUiYSL+erCFDPs0S3XdjELgN1q2jz
# y23zOlyhFvRGuuA4ZKxuZDV4pqBjDy3TQJP4494HDdVceaVJKecNvqATd76UPe/7
# 4ytaEB9NViiienLgEjq3SV7Y7e1DkYPZe7J7hhvZPrGMXeiJT4Qa8qEvWeSQOy2u
# M1jFtz7+MtOzAz2xsq+SOH7SnYAs9U5WkSE1JcM5bmR/U7qcD60ZI4TL9LoDho33
# X/DQUr+MlIe8wCF0JV8YKLbMJyg4JZg5SjbPfLGSrhwjp6lm7GEfauEoSZ1fiOIl
# XdMhSz5SxLVXPyQD8NF6Wy/VI+NwXQ9RRnez+ADhvKwCgl/bwBWzvRvUVUvnOaEP
# 6SNJvBi4RHxF5MHDcnrgcuck379GmcXvwhxX24ON7E1JMKerjt/sW5+v/N2wZuLB
# l4F77dbtS+dJKacTKKanfWeA5opieF+yL4TXV5xcv3coKPHtbcMojyyPQDdPweGF
# RInECUzF1KVDL3SV9274eCBYLBNdYJWaPk8zhNqwiBfenk70lrC8RqBsmNLg1oiM
# CwIDAQABo4IB7TCCAekwEAYJKwYBBAGCNxUBBAMCAQAwHQYDVR0OBBYEFEhuZOVQ
# BdOCqhc3NyK1bajKdQKVMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsGA1Ud
# DwQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaAFHItOgIxkEO5FAVO
# 4eqnxzHRI4k0MFoGA1UdHwRTMFEwT6BNoEuGSWh0dHA6Ly9jcmwubWljcm9zb2Z0
# LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1Jvb0NlckF1dDIwMTFfMjAxMV8wM18y
# Mi5jcmwwXgYIKwYBBQUHAQEEUjBQME4GCCsGAQUFBzAChkJodHRwOi8vd3d3Lm1p
# Y3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dDIwMTFfMjAxMV8wM18y
# Mi5jcnQwgZ8GA1UdIASBlzCBlDCBkQYJKwYBBAGCNy4DMIGDMD8GCCsGAQUFBwIB
# FjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2RvY3MvcHJpbWFyeWNw
# cy5odG0wQAYIKwYBBQUHAgIwNB4yIB0ATABlAGcAYQBsAF8AcABvAGwAaQBjAHkA
# XwBzAHQAYQB0AGUAbQBlAG4AdAAuIB0wDQYJKoZIhvcNAQELBQADggIBAGfyhqWY
# 4FR5Gi7T2HRnIpsLlhHhY5KZQpZ90nkMkMFlXy4sPvjDctFtg/6+P+gKyju/R6mj
# 82nbY78iNaWXXWWEkH2LRlBV2AySfNIaSxzzPEKLUtCw/WvjPgcuKZvmPRul1LUd
# d5Q54ulkyUQ9eHoj8xN9ppB0g430yyYCRirCihC7pKkFDJvtaPpoLpWgKj8qa1hJ
# Yx8JaW5amJbkg/TAj/NGK978O9C9Ne9uJa7lryft0N3zDq+ZKJeYTQ49C/IIidYf
# wzIY4vDFLc5bnrRJOQrGCsLGra7lstnbFYhRRVg4MnEnGn+x9Cf43iw6IGmYslmJ
# aG5vp7d0w0AFBqYBKig+gj8TTWYLwLNN9eGPfxxvFX1Fp3blQCplo8NdUmKGwx1j
# NpeG39rz+PIWoZon4c2ll9DuXWNB41sHnIc+BncG0QaxdR8UvmFhtfDcxhsEvt9B
# xw4o7t5lL+yX9qFcltgA1qFGvVnzl6UJS0gQmYAf0AApxbGbpT9Fdx41xtKiop96
# eiL6SJUfq/tHI4D1nvi/a7dLl+LrdXga7Oo3mXkYS//WsyNodeav+vyL6wuA6mk7
# r/ww7QRMjt/fdW1jkT3RnVZOT7+AVyKheBEyIXrvQQqxP/uozKRdwaGIm1dxVk5I
# RcBCyZt2WwqASGv9eZ/BvW1taslScxMNelDNMYIVWjCCFVYCAQEwgZUwfjELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEoMCYGA1UEAxMfTWljcm9z
# b2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAxMQITMwAAAd9r8C6Sp0q00AAAAAAB3zAN
# BglghkgBZQMEAgEFAKCBrjAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgor
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQg9y7cQKhQ
# 37+dgiOMuthF+FO77x+Qmsm16Yv+xkB5cwEwQgYKKwYBBAGCNwIBDDE0MDKgFIAS
# AE0AaQBjAHIAbwBzAG8AZgB0oRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
# BgkqhkiG9w0BAQEFAASCAQCbeFffvQQVUcC+hEY4NYGfnRGf5SMbHMUuiQEF2pxo
# /OWU309Xn740hg5rkkhadJzI6ZFk16vw9hyScjfIYVo0+3sOYRYllRQEbQH9uKu9
# iBjjX/1uGH33fyS6Zh8HG8qOd7F4Xdalq4rce4qSZKDtj1p0J+1I6pg1AFPukTot
# Ju3QADAAbe2xLT/3cOPe/4OuYcsLr2cphXiD+br3AyQCAnbWALN+0QdY7m66uojN
# 1Rm8cYOIKtnWErmx9kgfctYZGX9wwuv8nNEESNlX+XqHe2g7hTjnqJ7qWoiNP+5B
# O98+PZggL5CZI2ZV4thcr0ZkHYDTHUBXlPQ/h0eFQ2ffoYIS5DCCEuAGCisGAQQB
# gjcDAwExghLQMIISzAYJKoZIhvcNAQcCoIISvTCCErkCAQMxDzANBglghkgBZQME
# AgEFADCCAVAGCyqGSIb3DQEJEAEEoIIBPwSCATswggE3AgEBBgorBgEEAYRZCgMB
# MDEwDQYJYIZIAWUDBAIBBQAEIHlxJaQUZIeNoSJjAdyRp7DI00XjRTDbZtlUa+Vm
# KiGLAgZgiceNoJMYEjIwMjEwNDMwMTcyOTI3Ljg3WjAEgAIB9KCB0KSBzTCByjEL
# MAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
# bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjElMCMGA1UECxMcTWlj
# cm9zb2Z0IEFtZXJpY2EgT3BlcmF0aW9uczEmMCQGA1UECxMdVGhhbGVzIFRTUyBF
# U046OEE4Mi1FMzRGLTlEREExJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1w
# IFNlcnZpY2Wggg48MIIE8TCCA9mgAwIBAgITMwAAAUtPsqZI1eTCUQAAAAABSzAN
# BgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAeFw0y
# MDExMTIxODI1NTlaFw0yMjAyMTExODI1NTlaMIHKMQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBP
# cGVyYXRpb25zMSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVTTjo4QTgyLUUzNEYtOURE
# QTElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZTCCASIwDQYJ
# KoZIhvcNAQEBBQADggEPADCCAQoCggEBAKE2elDHdi4mv+K+hs+gu2lD16BQWXxM
# d1ZnpIAogl20/cvbgPf93reiaaaNmMLKtCb6P/W0cMDCNAa47Bi+fv15w8JB8AH3
# UmcSn/A/gEwXZJfIx/yT1HzhG2Eh18Yc9dNarOkIJ81aiVURxRWbwB3+vUuuKRE7
# 7goqjqyUNAkqyAoCl8FT/0ntG52+HDWsRDDQ2TUFEZaOsinv+5ahQh9HityXpTW6
# 06JgiicLzs8+kAlBcZGwN0qdUUXg2la8yLJ66Syfm3863DPzawaWd78c1CmYzOKB
# Hxxnx5cQMkk0hnGi/1YAcePbyBQTb0PyK8BPvTqKHG9O/nRljxbnW7ECAwEAAaOC
# ARswggEXMB0GA1UdDgQWBBRSqmp+0BKW57orct4+VNOfTUrrxjAfBgNVHSMEGDAW
# gBTVYzpcijGQ80N7fEYbxTNoWoVtVTBWBgNVHR8ETzBNMEugSaBHhkVodHRwOi8v
# Y3JsLm1pY3Jvc29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNUaW1TdGFQQ0Ff
# MjAxMC0wNy0wMS5jcmwwWgYIKwYBBQUHAQEETjBMMEoGCCsGAQUFBzAChj5odHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1RpbVN0YVBDQV8yMDEw
# LTA3LTAxLmNydDAMBgNVHRMBAf8EAjAAMBMGA1UdJQQMMAoGCCsGAQUFBwMIMA0G
# CSqGSIb3DQEBCwUAA4IBAQAW2rnVlz87UB8kri0QHY2vxsYRUPmpDyXyBchAysxl
# i110cf5waKqAX/gaa+Y9+XkUBiH6B//xh3erj+IPb4rgu0luz/e/qanIGXWZDi+6
# wrrl0DKlaaJPVbcWJeOyYIiSNIMOwosUFgfnIYWc0U4QyAv47u7iiwfjZ/zSdzZZ
# 2dlXr469bTflc9Xpm21QF8VYd0htSR04bU7afjImbXQ59pwi1nTx/OAwyoT5/9JO
# BVY0IdtHYRipNZrKsY/r2MzC1UP0EYZNa2LVeOm8TrIp07wf2e5GLcv4LqNie19o
# SYFNudMURX6RHHUI1ylJv2izzoIBR6FlTVpHNDoJD+mPMIIGcTCCBFmgAwIBAgIK
# YQmBKgAAAAAAAjANBgkqhkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNV
# BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jv
# c29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlm
# aWNhdGUgQXV0aG9yaXR5IDIwMTAwHhcNMTAwNzAxMjEzNjU1WhcNMjUwNzAxMjE0
# NjU1WjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYD
# VQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDCCASIwDQYJKoZIhvcN
# AQEBBQADggEPADCCAQoCggEBAKkdDbx3EYo6IOz8E5f1+n9plGt0VBDVpQoAgoX7
# 7XxoSyxfxcPlYcJ2tz5mK1vwFVMnBDEfQRsalR3OCROOfGEwWbEwRA/xYIiEVEMM
# 1024OAizQt2TrNZzMFcmgqNFDdDq9UeBzb8kYDJYYEbyWEeGMoQedGFnkV+BVLHP
# k0ySwcSmXdFhE24oxhr5hoC732H8RsEnHSRnEnIaIYqvS2SJUGKxXf13Hz3wV3Ws
# vYpCTUBR0Q+cBj5nf/VmwAOWRH7v0Ev9buWayrGo8noqCjHw2k4GkbaICDXoeByw
# 6ZnNPOcvRLqn9NxkvaQBwSAJk3jN/LzAyURdXhacAQVPIk0CAwEAAaOCAeYwggHi
# MBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBTVYzpcijGQ80N7fEYbxTNoWoVt
# VTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYDVR0T
# AQH/BAUwAwEB/zAfBgNVHSMEGDAWgBTV9lbLj+iiXGJo0T2UkFvXzpoYxDBWBgNV
# HR8ETzBNMEugSaBHhkVodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2NybC9w
# cm9kdWN0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcmwwWgYIKwYBBQUHAQEE
# TjBMMEoGCCsGAQUFBzAChj5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2Nl
# cnRzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNydDCBoAYDVR0gAQH/BIGVMIGS
# MIGPBgkrBgEEAYI3LgMwgYEwPQYIKwYBBQUHAgEWMWh0dHA6Ly93d3cubWljcm9z
# b2Z0LmNvbS9QS0kvZG9jcy9DUFMvZGVmYXVsdC5odG0wQAYIKwYBBQUHAgIwNB4y
# IB0ATABlAGcAYQBsAF8AUABvAGwAaQBjAHkAXwBTAHQAYQB0AGUAbQBlAG4AdAAu
# IB0wDQYJKoZIhvcNAQELBQADggIBAAfmiFEN4sbgmD+BcQM9naOhIW+z66bM9TG+
# zwXiqf76V20ZMLPCxWbJat/15/B4vceoniXj+bzta1RXCCtRgkQS+7lTjMz0YBKK
# dsxAQEGb3FwX/1z5Xhc1mCRWS3TvQhDIr79/xn/yN31aPxzymXlKkVIArzgPF/Uv
# eYFl2am1a+THzvbKegBvSzBEJCI8z+0DpZaPWSm8tv0E4XCfMkon/VWvL/625Y4z
# u2JfmttXQOnxzplmkIz/amJ/3cVKC5Em4jnsGUpxY517IW3DnKOiPPp/fZZqkHim
# bdLhnPkd/DjYlPTGpQqWhqS9nhquBEKDuLWAmyI4ILUl5WTs9/S/fmNZJQ96LjlX
# dqJxqgaKD4kWumGnEcua2A5HmoDF0M2n0O99g/DhO3EJ3110mCIIYdqwUB5vvfHh
# AN/nMQekkzr3ZUd46PioSKv33nJ+YWtvd6mBy6cJrDm77MbL2IK0cs0d9LiFAR6A
# +xuJKlQ5slvayA1VmXqHczsI5pgt6o3gMy4SKfXAL1QnIffIrE7aKLixqduWsqdC
# osnPGUFN4Ib5KpqjEWYw07t0MkvfY3v1mYovG8chr1m1rtxEPJdQcdeh0sVV42ne
# V8HR3jDA/czmTfsNv11P6Z0eGTgvvM9YBS7vDaBQNdrvCScc1bN+NR4Iuto229Nf
# j950iEkSoYICzjCCAjcCAQEwgfihgdCkgc0wgcoxCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xJTAjBgNVBAsTHE1pY3Jvc29mdCBBbWVyaWNhIE9w
# ZXJhdGlvbnMxJjAkBgNVBAsTHVRoYWxlcyBUU1MgRVNOOjhBODItRTM0Ri05RERB
# MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYF
# Kw4DAhoDFQCROjP3t+x4fE05RJDk79sFVIX57qCBgzCBgKR+MHwxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqGSIb3DQEBBQUAAgUA5DZAPDAiGA8yMDIx
# MDQzMDE2MzcxNloYDzIwMjEwNTAxMTYzNzE2WjB3MD0GCisGAQQBhFkKBAExLzAt
# MAoCBQDkNkA8AgEAMAoCAQACAhxKAgH/MAcCAQACAhN4MAoCBQDkN5G8AgEAMDYG
# CisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAIAgEA
# AgMBhqAwDQYJKoZIhvcNAQEFBQADgYEAj+Wulfhu/JpNouotbjTwjOJ0Woz7ZqcL
# iyFNWyyy9Xjwnqrob5NsiDsg89Z7zHiivtL4pEtuDa1UF1yBvCuXtl34zftALDOa
# Jl2mnaJ+l/6grgsci47u48kQ5LMi652FkGaHRTd5QOmMB+ot6UyfgHbx+ugweQQB
# nhTjjy6t80sxggMNMIIDCQIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMAITMwAAAUtPsqZI1eTCUQAAAAABSzANBglghkgBZQMEAgEFAKCCAUowGgYJ
# KoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCDgZk7hms7H
# ApUOB3z6f9QLICnWbq+Jzr/TKBQMeVB5DTCB+gYLKoZIhvcNAQkQAi8xgeowgecw
# geQwgb0EIGv27oQieexlgS2z8WP+sgW/RhlbXKeFco4/aFU9RTkjMIGYMIGApH4w
# fDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMd
# TWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAFLT7KmSNXkwlEAAAAA
# AUswIgQgNTHLrjaW3yvxplPIiJA9ClTScihEOG106J36ryr7EeEwDQYJKoZIhvcN
# AQELBQAEggEAAofOSUUP1rCjmwljBa94MBbdUpa7zM08/BYWIg0oDgT2WyTllKV0
# AYCH0Qf/jdyILNzc2q0J7q53JzX80gh/9ujCWk3mZvZoj+BAu/3GjBy9CWRRAw4h
# EaH0HqT7p+kzHdui1j+ZINJt36TAKeRbcxgGvI+YdJ9jkKLKws55sC7gqBr1NLlq
# PLpWxQFXSTn0BoV4G9LFUh+ucrmYutxVO2sucHcRDQL+cnYAjxyEu1k9HMNLTY+m
# lwWnx4M49xd1TR+PN8tpmcQSMfZNTHzI7Cq6k8ikYukmAUjPVe2c513A49fC4lJx
# 6lw5cGbCz8AVAohGlAwWtZq04WMX/XUeGA==
# SIG # End signature block
