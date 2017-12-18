###############################################################################################################
# Language     :  PowerShell 5
# Filename     :  PowerC2.ps1 
# Author       :  Theodore (Tad) Miller (https://github.com/tadmiller)
# Description  :  All-Powershell Command & Control Server
# Repository   :  https://github.com/tadmiller/PowerC2
###############################################################################################################

<#
    .SYNOPSIS
    Simple Powershell Command & Control Server

    .DESCRIPTION
    This server provides a simple interface in which an individual can conduct C2 operations.
    It provides basic functionality that a Pentester might need, implemented client side.

    .EXAMPLE
    .\PowerC2.ps1

    Initializing Shell.........OK

    __________                            _________  ________  
    \______   \______  _  __ ___________  \_   ___ \ \_____  \ 
     |     ___/  _ \ \/ \/ // __ \_  __ \ /    \  \/  /  ____/ 
     |    |  (  <_> )     /\  ___/|  | \/ \     \____/       \ 
     |____|   \____/ \/\_/  \___  >__|     \______  /\_______ \
                                \/                \/         \/
    Welcome to Power C2
    Type HELP to list the commands available

    $: listen 9001

    Started listener on 0.0.0.0:9001


    $: sessions
    0	 127.0.0.1 : 51069

    $: use 0

    Using session 0

     0\>: whoami

    QUANTUMV2\tadmi

     0\>: ret

    Leaving session active...

    .LINK
    https://github.com/tadmiller/PowerC2/blob/master/README.md
#>

$MENU_CMDS = @{}
$SESSION_CMDS = @{}
$ACTIVE_LISTENERS = New-Object System.Collections.ArrayList
$ACTIVE_CLIENTS = New-Object System.Collections.ArrayList
$ACTIVE_RUNSPACES = New-Object System.Collections.ArrayList


$CLIENT_FINDER = {

    if ($listener -eq $null)
    {
        exit 1
    }

    if ($listener.GetType() -ne [System.Net.Sockets.TcpListener])
    {
        Write-Host -ForegroundColor Red "Listener is not a tcp listener. It is" $listener.GetType()
        exit 1
    }

    while ($true)
    {
        Write-Host -ForegroundColor Magenta "Awaiting client connection..."

        $client = $listener.AcceptTcpClient()

        if ($client -ne $null)
        {
            $ACTIVE_CLIENTS.Add($client)
        }
    }
}

function ExitC2()
{
    Write-Host ""
    Write-Host -ForegroundColor Red "Exiting Application..."

    foreach ($l in $ACTIVE_LISTENERS)
    {
        if ($l -ne $null)
        {
            if ($l.GetType() -eq [System.Net.Sockets.TcpListener])
            {
                $l.Stop() > $null
            }
        }
    }

    foreach ($l in $ACTIVE_RUNSPACES)
    {
        if ($l -ne $null)
        {
            #Write-Host -ForegroundColor Yellow "Stopping runspace"
            $l.Dispose() > $null
        }
    }

    foreach ($l in $ACTIVE_CLIENTS)
    {
        if ($l -ne $null)
        {
            $stream = $l.GetStream()
            SendMessage $stream "quit"
            $stream.Dispose() > $null
            $l.Dispose() > $null
        }
    }

    exit 1 > $null
}

function MenuHelp()
{
    Write-Host "`n"
    $MENU_CMDS.GetEnumerator() | % { $_.Key + "`t | `t" + $_.Value }
    Write-Host "`n"
}

function SessionHelp()
{
    Write-Host "`n"
    $SESSION_CMDS.GetEnumerator() | % { $_.Key + "`t | `t" + $_.Value }
    Write-Host "`n"
}

function AddListener($port)
{
    $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, $port)
    Write-Host -ForegroundColor Yellow "`nStarted listener on" $listener.LocalEndpoint
    #Write-Host -Foreground Yellow $listener.LocalEndpoint "active"
    $listener.Start()
    $ACTIVE_LISTENERS.Add($listener) > $null

    $runSpace = [RunSpaceFactory]::CreateRunspace()
    $runSpace.Open()
    $runSpace.SessionStateProxy.SetVariable("ACTIVE_LISTENERS", $ACTIVE_LISTENERS)
    $runSpace.SessionStateProxy.SetVariable("ACTIVE_CLIENTS", $ACTIVE_CLIENTS)
    $runSpace.SessionStateProxy.SetVariable("Listener", $listener)
    $PS = [PowerShell]::Create()
    $PS.Runspace = $runSpace
    $PS.AddScript($CLIENT_FINDER).BeginInvoke()
    $ACTIVE_RUNSPACES.Add($runSpace)
}

function ListShells()
{
    $i = 0
    foreach ($t in $ACTIVE_CLIENTS)
    {
        if ($t -ne $null)
        {
            if ($t.GetType() -eq [System.Net.Sockets.TcpClient])
            {
                Write-Host -Foreground Yellow "$i`t" $t.Client.RemoteEndPoint.Address ":" $t.Client.RemoteEndPoint.Port
                $i++
            }
        }
    }
}

function ListListeners()
{
    Write-Host -Foreground Cyan "`nListing active listeners`n"
    foreach ($t in $ACTIVE_LISTENERS)
    {
        if ($t -ne $null -and $t.GetType() -eq [System.Net.Sockets.TcpListener])
        {
            Write-Host -Foreground Yellow $t.LocalEndpoint
        }
    }
}

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

# Given an active session / shell, switch to it and allow the user to interact with it.
function UseShell($num)
{
    # Make sure that we don't iterate over the length of the list of clients.
    if ($num -ge $ACTIVE_CLIENTS.Length)
    {
        Write-Host -ForegroundColor Red "No such client is available"
        return
    }

    $client = $ACTIVE_CLIENTS.Item($num -as [int])

    # If the client is null, then we don't want to attempt to invoke functions on it.
    if ($client -eq $null)
    {
        Write-Host -ForegroundColor Red "No such client is available"
        return
    }

    Write-Host -ForegroundColor Yellow "`nUsing session" $num

    # Get the data stream between the client and the server.
    $stream = $client.GetStream()
    [byte[]] $buffer = New-Object byte[] 5KB

    # Get a command from the application user, and execute it on the C2 agent.
    do
    {
        $msg = Read-Host "`n"$num"\>"

        if ($msg -eq "help")
        {
            SessionHelp
        }
        else
        {
            SendMessage $stream $msg
            $res = ReceiveData $stream $buffer
            Write-Host ""
            Write-Host -ForegroundColor Cyan $res
        }

    } while ($msg -ne "ret" -and $msg -ne "quit")

    # If quitting the session, we need to remove it a list of active sessions, and close the client connection properly.
    if ($msg -eq "quit")
    {
        $stream.Dispose()
        $client.Dispose()
        $ACTIVE_CLIENTS.RemoveAt($num -as [int])
    }
}

# For some fun in loading
function Dot()
{
    Start-Sleep -m 100
    Write-Host -ForegroundColor Yellow -NoNewLine "."
}

# The application shell
function InitMenu()
{
    Write-Host ""
    Write-Host -ForegroundColor Yellow -NoNewLine "Initializing Shell"
    
    Dot
    $MENU_CMDS.Add("HELP    ", "Lists commands available on the current menu")
    Dot
    $MENU_CMDS.Add("LISTEN x", "Sets up a listener on port x")
    Dot
    $MENU_CMDS.Add("SESSIONS", "Lists the shells available from hosts connected to the server")
    Dot
    $MENU_CMDS.Add("QUIT    ", "Exit the application")
    Dot
    $MENU_CMDS.Add("USE x   ", "Select an active session to use and switch to its context")
    Dot
    $SESSION_CMDS.Add("HELP    ", "Lists commands available on the current menu")
    Dot
    $SESSION_CMDS.Add("LS      ", "Lists current directory C2 agent is running from")
    Dot
    $SESSION_CMDS.Add("EXIT    ", "Exit from the current session, and exit the agent running on the client")
    Dot
    $SESSION_CMDS.Add("RETURN  ", "Return from the current session")
    #$SESSION_CMDS.Add("LS      ", "Lists current directory C2 agent is running from")

    Write-Host -ForegroundColor Green "OK`n"

    Write-Host -ForegroundColor Magenta "__________                            _________  ________  
\______   \______  _  __ ___________  \_   ___ \ \_____  \ 
 |     ___/  _ \ \/ \/ // __ \_  __ \ /    \  \/  /  ____/ 
 |    |  (  <_> )     /\  ___/|  | \/ \     \____/       \ 
 |____|   \____/ \/\_/  \___  >__|     \______  /\_______ \
                            \/                \/         \/"

    Write-Host -Foreground Yellow "Welcome to Power C2"
    Write-Host -Foreground Yellow "Type HELP to list the commands available"

    $con = 0

    do
    {
        $msg = Read-Host "`n$"

        switch -Wildcard ($msg)
        {
            "help" {
                MenuHelp
                break
            }
            "listeners" {
                ListListeners
                break
            }
            "listen*" {
                AddListener $msg.SubString(7, $msg.Length - 7)
                break
            }
            "sessions" {
                ListShells
                break
            }
            "use*" {
                UseShell $msg.SubString(4, $msg.Length - 4) -as [int]
                break
            }
        }
    } while ($msg -ne "q" -and $msg -ne "quit" -and $msg -ne "exit")

    ExitC2
}

InitMenu