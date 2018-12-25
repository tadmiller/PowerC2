# PowerC2

## Description

PowerShell-based Command & Control Server designed for pentesters

## Installation

Run PowerC2.ps1 to initialize a PowerC2 server.

In PowerAgent.ps1, add the IP address of your server and the port for it to connect back on.

## Example

.\PowerC2.ps1

Initializing Shell.........OK

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
