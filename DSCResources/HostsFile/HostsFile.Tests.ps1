try
{
    $prefix = [guid]::NewGuid().Guid -replace '[^a-z0-9]'

    Remove-Module [H]ostsFile
    Import-Module $PSScriptRoot\HostsFile.psm1 -Prefix $prefix

    Describe 'Get-TargetResource' {
        # This is barely worth testing since it's essentially just a wrapper around the same logic
        # as Test-TargetResource.  (If Test-TargetResource is False, the hashtable returned by
        # Get-TargetResource will have Ensure = 'Absent'.)  There are no other non-key properties
        # to return data for.

        Mock -ModuleName HostsFile Get-Content -ParameterFilter { $Path -eq "$env:windir\system32\drivers\etc\hosts" } {
            Get-Content 'TestDrive:\hosts'
        }

        It 'Returns a hashtable with Ensure set to Absent if the file does not contain the specified ip / hostname' {
            $ip       = '1.2.3.4'
            $hostname = 'test.com'
            
            Setup -File hosts "    $ip SomeOtherHostname.com # $hostname Commented Out"

            $hashTable = & "Get-${prefix}TargetResource" -IPAddress $ip -HostName $hostname

            $hashTable              | Should Not Be $null
            $hashTable.GetType()    | Should Be ([hashtable])
            $hashTable['IPAddress'] | Should Be $ip
            $hashTable['HostName']  | Should Be $hostname
            $hashTable['Ensure']    | Should Be 'Absent'
        }

        It 'Returns a hashtable with Ensure set to Absent if the file does not contain the specified ip / hostname' {
            $ip       = '1.2.3.4'
            $hostname = 'test.com'
            
            Setup -File hosts "   $ip $hostname  # some comment"

            $hashTable = & "Get-${prefix}TargetResource" -IPAddress $ip -HostName $hostname

            $hashTable              | Should Not Be $null
            $hashTable.GetType()    | Should Be ([hashtable])
            $hashTable['IPAddress'] | Should Be $ip
            $hashTable['HostName']  | Should Be $hostname
            $hashTable['Ensure']    | Should Be 'Present'
        }
    }

    Describe 'Test-TargetResource' {
        Mock -ModuleName HostsFile Get-Content -ParameterFilter { $Path -eq "$env:windir\system32\drivers\etc\hosts" } {
            Get-Content 'TestDrive:\hosts'
        }

        It 'Returns false when the IP address does not exist and Ensure = Present' {
            $actualIP = '1.2.3.4'
            $partialMatch = '11.2.3.4'

            Setup -File hosts "
                # $actualIP Comment Line
                $partialMatch PartialMatch
            "

            $entryExists = & "Test-${prefix}TargetResource" -IPAddress $actualIP -HostName 'Whatever' -Ensure 'Present'
            $entryExists | Should Be $false
        }

        It 'Returns false when the IP address exists, but does not have the proper hostname, and Ensure = Present' {
            $actualIP = '1.2.3.4'
            $actualHostName = 'test.mocked.org'

            Setup -File hosts "
                $actualIP SomeOtherHostName.com
            "

            $entryExists = & "Test-${prefix}TargetResource" -IPAddress $actualIP -HostName $actualHostName -Ensure 'Present'
            $entryExists | Should Be $false
        }

        It 'Returns false when the IP address exists, the proper hostname is on the line but commented out, and Ensure = Present' {
            $actualIP = '1.2.3.4'
            $actualHostName = 'test.mocked.org'

            Setup -File hosts "
                $actualIP SomeOtherHostName.com # $actualHostName Commented Out
            "

            $entryExists = & "Test-${prefix}TargetResource" -IPAddress $actualIP -HostName $actualHostName -Ensure 'Present'
            $entryExists | Should Be $false
        }

        It 'Returns true when the IP address exists, the hostname is on the line (in any order), and Ensure = Present' {
            $actualIP = '1.2.3.4'
            $actualHostName = 'test.mocked.org'

            Setup -File hosts "
                $actualIP SomeOtherHostName.com $actualHostName
            "

            $entryExists = & "Test-${prefix}TargetResource" -IPAddress $actualIP -HostName $actualHostName -Ensure 'Present'
            $entryExists | Should Be $true
        }
    }

    Describe 'Set-TargetResource' {
        Mock -ModuleName HostsFile Get-Content -ParameterFilter { $Path -eq "$env:windir\system32\drivers\etc\hosts" } {
            Get-Content 'TestDrive:\hosts'
        }

        Mock -ModuleName HostsFile Set-Content { }

        Context 'Ensure = Present' {
            It 'Adding new lines to a file when it does not contain the IP address' {
                $ip       = '1.2.3.4'
                $hostname = 'test.com'

                $null = New-Item -Path TestDrive:\hosts -ItemType File -Force

                & "Set-${prefix}TargetResource" -IPAddress $ip -HostName $hostname -Ensure 'Present'

                Assert-MockCalled -ModuleName HostsFile -Scope It Set-Content -ParameterFilter { $Value -contains "$ip $hostname" }
            }

            It 'Adds hostnames to files that contain the IP address, but not the hostname' {
                $indent           = '   '
                $ip               = '1.2.3.4'
                $hostname         = 'test.com'
                $existingHostname = 'other.com'
                $comment          = 'I am a comment'
                $firstLine        = '5.6.7.8 someotherhostname.org # second comment'
                $thirdLine        = ' # just a comment'

                Set-Content TestDrive:\hosts $firstLine, "${indent}$ip $existingHostname # $comment", $thirdLine

                & "Set-${prefix}TargetResource" -IPAddress $ip -HostName $hostname -Ensure 'Present'

                $parameterFilter = {
                    $Value.Count -eq 3 -and
                    $Value[0] -eq $firstLine -and
                    $value[2] -eq $thirdLine -and
                    $Value[1] -eq "${indent}$ip $existingHostname $hostname # $comment"
                }

                Assert-MockCalled -ModuleName HostsFile -Scope It Set-Content -ParameterFilter $parameterFilter
            }

            It 'Properly handles malformed lines that contain an IP address but no hostnames' {
                $ip          = '1.2.3.4'
                $hostname    = 'test.com'
                $secondLine  = '5.6.7.8 second.line.com'
                
                Set-Content TestDrive:\hosts "$ip", $secondLine

                & "Set-${prefix}TargetResource" -IPAddress $ip -HostName $hostname -Ensure 'Present'

                $parameterFilter = {
                    $Value.Count -eq 2 -and
                    $Value[0] -eq "$ip $hostname" -and 
                    $Value[1] -eq $secondLine
                }

                Assert-MockCalled -ModuleName HostsFile -Scope It Set-Content -ParameterFilter $parameterFilter                
            }

            It 'Does not modify a file that already has the correct information' {
                $ip       = '1.2.3.4'
                $hostname = 'test.com'

                Setup -File hosts "$ip $hostname"

                & "Set-${prefix}TargetResource" -IPAddress $ip -HostName $hostname -Ensure 'Present'

                Assert-MockCalled -ModuleName HostsFile -Scope It Set-Content -Times 0
            }
        }

        Context 'Ensure = Absent' {
            It 'Does not modify a file when it does not contain the IP address' {
                $ip       = '1.2.3.4'
                $hostname = 'test.com'

                Setup -File hosts '5.6.7.8 Whatever.com'

                & "Set-${prefix}TargetResource" -IPAddress $ip -HostName $hostname -Ensure 'Absent'

                Assert-MockCalled -ModuleName HostsFile -Scope It Set-Content -Times 0
            }

            It 'Does not modify a file when it contains the IP address but not the hostname' {
                $ip       = '1.2.3.4'
                $hostname = 'test.com'

                Setup -File hosts "$ip Whatever.com"

                & "Set-${prefix}TargetResource" -IPAddress $ip -HostName $hostname -Ensure 'Absent'

                Assert-MockCalled -ModuleName HostsFile -Scope It Set-Content -Times 0
            }

            It 'Removes hostnames to files that contain the IP address and multiple hostnames' {
                $indent        = '   '
                $ip            = '1.2.3.4'
                $hostname      = 'test.com'
                $otherHostName = 'other.com'
                $comment       = 'I am a comment'

                Setup -File hosts "${indent}$ip $hostname $otherHostName # $comment"

                & "Set-${prefix}TargetResource" -IPAddress $ip -HostName $hostname -Ensure 'Absent'

                $parameterFilter = {
                    $Value.Count -eq 1 -and
                    $Value[0] -eq "${indent}$ip $otherHostName # $comment"
                }

                Assert-MockCalled -ModuleName HostsFile -Scope It Set-Content -ParameterFilter $parameterFilter
            }

            It 'Removes the whole line for files that contain the IP address with only the hostname to be removed' {
                $ip         = '1.2.3.4'
                $hostname   = 'test.com'
                $secondLine = '# Just a comment.'

                Set-Content TestDrive:\hosts "    $ip $hostname # A Comment", $secondLine

                & "Set-${prefix}TargetResource" -IPAddress $ip -HostName $hostname -Ensure 'Absent'

                $parameterFilter = {
                    $Value.Count -eq 1 -and
                    $Value[0] -eq $secondLine
                }

                Assert-MockCalled -ModuleName HostsFile -Scope It Set-Content -ParameterFilter $parameterFilter
            }
        }
    }
}
finally
{
    Remove-Module [H]ostsFile
}
