$script:HostsFilePath = "${env:windir}\system32\drivers\etc\hosts"

# Fallback message strings in en-US
DATA localizedData {
    # same as culture = "en-US"
ConvertFrom-StringData @'
    CheckingHostsFileEntry=Checking if the hosts file entry exists.
    HostsFileEntryFound=Found a hosts file entry for {0} and {1}.
    HostsFileEntryNotFound=Did not find a hosts file entry for {0} and {1}.
    HostsFileShouldNotExist=Hosts file entry exists while it should not.
    HostsFileEntryShouldExist=Hosts file entry does not exist while it should.
    CreatingHostsFileEntry=Creating a hosts file entry with {0} and {1}.
    RemovingHostsFileEntry=Removing a hosts file entry with {0} and {1}.
    HostsFileEntryAdded=Created the hosts file entry for {0} and {1}.
    HostsFileEntryRemoved=Removed the hosts file entry for {0} and {1}.
    AnErrorOccurred=An error occurred while creating hosts file entry: {1}.
    InnerException=Nested error trying to create hosts file entry: {1}.
'@
}

if (Test-Path $PSScriptRoot\en-us) {
    Import-LocalizedData LocalizedData -filename HostsFileProvider.psd1
}

function Get-TargetResource {
    [OutputType([Hashtable])]
    param (
        [parameter(Mandatory = $true)]
        [string]
        $hostName,
        [parameter(Mandatory = $true)]
        [string]
        $ipAddress
    )

    $Configuration = @{
        HostName = $hostName
        IPAddress = $IPAddress
    }

    Write-Verbose $localizedData.CheckingHostsFileEntry
    try {
        if (HostsEntryExists -IPAddress $ipAddress -HostName $hostName) {
            Write-Verbose ($localizedData.HostsFileEntryFound -f $hostName, $ipAddress)
            $Configuration.Add('Ensure','Present')
        } else {
            Write-Verbose ($localizedData.HostsFileEntryNotFound -f $hostName, $ipAddress)
            $Configuration.Add('Ensure','Absent')
        }
        return $Configuration
    } catch {
        $exception = $_
        Write-Verbose ($LocalizedData.AnErrorOccurred -f $name, $exception.message)
        while ($exception.InnerException -ne $null)
        {
            $exception = $exception.InnerException
            Write-Verbose ($LocalizedData.InnerException -f $name, $exception.message)
        }
    }
}

function Set-TargetResource {
    param (
        [parameter(Mandatory = $true)]
        [string]
        $hostName,
        [parameter(Mandatory = $true)]
        [string]
        $ipAddress,
        [parameter()]
        [ValidateSet('Present','Absent')]
        [string]
        $Ensure = 'Present'
    )

    try {
        if ($Ensure -eq 'Present') {
            Write-Verbose ($localizedData.CreatingHostsFileEntry -f $hostName, $ipAddress)
            AddHostsEntry -IPAddress $ipAddress -HostName $hostName
            Write-Verbose ($localizedData.HostsFileEntryAdded -f $hostName, $ipAddress)
        } else {
            Write-Verbose ($localizedData.RemovingHostsFileEntry -f $hostName, $ipAddress)
            RemoveHostsEntry -IPAddress $ipAddress -HostName $hostName
            Write-Verbose ($localizedData.HostsFileEntryRemoved -f $hostName, $ipAddress)
        }
    } catch {
        $exception = $_
        Write-Verbose ($LocalizedData.AnErrorOccurred -f $name, $exception.message)
        while ($exception.InnerException -ne $null) {
            $exception = $exception.InnerException
            Write-Verbose ($LocalizedData.InnerException -f $name, $exception.message)
        }
    }
}

function Test-TargetResource
{
    [OutputType([boolean])]
    param (
        [parameter(Mandatory = $true)]
        [string]
        $hostName,
        [parameter(Mandatory = $true)]
        [string]
        $ipAddress,
        [parameter()]
        [ValidateSet('Present','Absent')]
        [string]
        $Ensure = 'Present'
    )

    try {
        Write-Verbose $localizedData.CheckingHostsFileEntry
        $entryExist = HostsEntryExists -IPAddress $ipAddress -HostName $hostName

        if ($Ensure -eq "Present") {
            if ($entryExist) {
                Write-Verbose ($localizedData.HostsFileEntryFound -f $hostName, $ipAddress)
                return $true
            } else {
                Write-Verbose ($localizedData.HostsFileEntryShouldExist -f $hostName, $ipAddress)
                return $false
            }
        } else {
            if ($entryExist) {
                Write-Verbose $localizedData.HostsFileShouldNotExist
                return $false
            } else {
                Write-Verbose $localizedData.HostsFileEntryNotFound
                return $true
            }
        }
    } catch {
        $exception = $_
        Write-Verbose ($LocalizedData.AnErrorOccurred -f $name, $exception.message)
        while ($exception.InnerException -ne $null) {
            $exception = $exception.InnerException
            Write-Verbose ($LocalizedData.InnerException -f $name, $exception.message)
        }
    }
}

function HostsEntryExists {
    param (
        [string] $IPAddress,
        [string] $HostName
    )

    foreach ($line in Get-Content $script:HostsFilePath) {
        $parsed = ParseEntryLine -Line $line
        if ($parsed.IPAddress -eq $IPAddress) {
            return $parsed.HostNames -contains $HostName
        }
    }

    return $false
}

function AddHostsEntry {
    param (
        [string] $IPAddress,
        [string] $HostName
    )

    $content = @(Get-Content $script:HostsFilePath)
    $length = $content.Length

    $foundMatch = $false
    $dirty = $false

    for ($i = 0; $i -lt $length; $i++) {
        $parsed = ParseEntryLine -Line $content[$i]

        if ($parsed.IPAddress -ne $ipAddress) { continue }
        
        $foundMatch = $true

        if ($parsed.HostNames -notcontains $hostName) {
            $parsed.HostNames += $hostName
            $content[$i] = ReconstructLine -ParsedLine $parsed
            $dirty = $true
            # Hosts files shouldn't strictly have the same IP address on multiple lines; should we just break here?
            # Or is it better to search for all matching lines in a malformed file, and modify all of them?
        }
    }

    if (-not $foundMatch) {
        $content += "$ipAddress $hostName"
        $dirty = $true
    }

    if ($dirty) {
        Set-Content $script:HostsFilePath -Value $content
    }
}

function RemoveHostsEntry {
    param (
        [string] $IPAddress,
        [string] $HostName
    )

    $content = @(Get-Content $script:HostsFilePath)
    $length = $content.Length

    $placeholder = New-Object psobject
    $dirty = $false

    for ($i = 0; $i -lt $length; $i++) {
        $parsed = ParseEntryLine -Line $content[$i]

        if ($parsed.IPAddress -ne $IPAddress) { continue }
        
        if ($parsed.HostNames -contains $HostName) {
            $dirty = $true

            if ($parsed.HostNames.Count -eq 1) {
                # We're removing the only hostname from this line; just remove the whole line
                $content[$i] = $placeholder
            } else {
                $parsed.HostNames = $parsed.HostNames -ne $HostName
                $content[$i] = ReconstructLine -ParsedLine $parsed
            }
        }
    }

    if ($dirty) {
        $content = $content -ne $placeholder
        Set-Content $script:HostsFilePath -Value $content
    }
}

function ParseEntryLine {
    param ([string] $Line)

    $indent    = ''
    $ipAddress = ''
    $hostnames = @()
    $comment   = ''

    $regex = '^' +
             '(?<indent>\s*)' +
             '(?<ipAddress>\S+)' +
             '(?:' +
                 '\s+' +
                 '(?<hostNames>[^#]*)' +
                 '(?:#\s*(?<comment>.*))?' +
             ')?' +
             '\s*' +
             '$'

    if ($line -match $regex)
    {
        $indent    = $matches['indent']
        $ipAddress = $matches['ipAddress']
        $hostnames = $matches['hostNames'] -split '\s+' -match '\S'
        $comment   = $matches['comment']
    }

    return [pscustomobject] @{
        Indent    = $indent
        IPAddress = $ipAddress
        HostNames = $hostnames
        Comment   = $comment
    }
}

function ReconstructLine {
    param ([object] $ParsedLine)

    if ($ParsedLine.Comment) {
        $comment = " # $($ParsedLine.Comment)"
    } else {
        $comment = ''
    }

    return '{0}{1} {2}{3}' -f $ParsedLine.Indent, $ParsedLine.IPAddress, ($ParsedLine.HostNames -join ' '), $comment
}

Export-ModuleMember -Function Test-TargetResource,Set-TargetResource,Get-TargetResource
