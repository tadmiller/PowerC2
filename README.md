# PowerC2

Simple Powershell Command & Control Server

## Description

This server provides a simple interface in which an individual can conduct C2 operations.
It provides basic functionality that a Pentester might need, implemented client side.

## Example

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