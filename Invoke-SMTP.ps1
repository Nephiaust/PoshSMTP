#Requires -Version 5.1
#Requires -Modules PoShLog

$Settings = ([xml](Get-Content ./config.xml)).configuration

# *******************************************************
# *******************************************************
# **                                                   **
# **            DO NOT EDIT BELOW THIS BLOCK           **
# **                                                   **
# **                INITIALISATION BLOCK               **
# **                                                   **
# *******************************************************
# *******************************************************

$CurrentModules = Get-Module

If ($Settings.Logging.EventLogs.enabled -eq 1) { Import-Module PoShLog.Sinks.EventLog }
$LogLevel = $Settings.Logging.Defaults.Verbosity.ToString()

$LoggingOutput = 'Starting Logging. Initialised the Default'

$LoggingCommand = "New-Logger | Set-MinimumLevel -Value $LogLevel | "
If ($Settings.Logging.File.enabled -eq 1) {
  $LogLevel = $Settings.Logging.File.Verbosity.ToString()
  $LogFormat = '"' + $Settings.Logging.File.Format.ToString() + '"'
  $LogFile = $Settings.Logging.File.Logfile.ToString()
  $LogRollover = $Settings.Logging.File.Rollover.When.ToString()
  $LogRetain = $Settings.Logging.File.Rollover.Retains.ToInt32($null)
  $LoggingOutput += ", File"
  $LoggingCommand = $LoggingCommand + "Add-SinkFile -RestrictedToMinimumLevel $LogLevel -OutputTemplate $LogFormat -Path $LogFile -RollingInterval $LogRollover -RetainedFileCountLimit $LogRetain | "
}
If ($Settings.Logging.Console.enabled -eq 1) {
  $LogLevel = $Settings.Logging.Console.Verbosity.ToString()
  $LogFormat = '"' + $Settings.Logging.Console.Format.ToString() + '"'
  $LoggingOutput += ", Console"
  $LoggingCommand = $LoggingCommand + "Add-SinkConsole -RestrictedToMinimumLevel $LogLevel -OutputTemplate $LogFormat | "
}
If ($Settings.Logging.EventLogs.enabled -eq 1) {
  $LogLevel = $Settings.Logging.EventLogs.Verbosity.ToString()
  $LogFormat = '"' + $Settings.Logging.EventLogs.Format.ToString() + '"'
  $LogName = '"' + $Settings.Logging.EventLogs.EventLog.ToString() + '"'
  $LoggingOutput += ", EventLogs"
  $LoggingCommand = $LoggingCommand + "Add-SinkEventLog -RestrictedToMinimumLevel $LogLevel -OutputTemplate $LogFormat -Source $LogName | "
}
If ($Settings.Logging.PowerShell.enabled -eq 1) {
  $LogLevel = $Settings.Logging.PowerShell.Verbosity.ToString()
  $LogFormat = '"' + $Settings.Logging.PowerShell.Format.ToString() + '"'
  $LoggingOutput += ", PowerShell"
  $LoggingCommand = $LoggingCommand + "Add-SinkPowerShell -RestrictedToMinimumLevel $LogLevel -OutputTemplate $LogFormat | "
}

$LoggingCommand = $LoggingCommand + "Start-Logger"
Invoke-Expression $LoggingCommand
$LoggingOutput += ' modules.'
Write-InformationLog $LoggingOutput

# *******************************************************
# *******************************************************
# **                                                   **
# **              INTERNAL VARIABLES BLOCK             **
# **                                                   **
# *******************************************************
# *******************************************************

Write-DebugLog 'Setting the IP address to listen on'
If ($Settings.Server.Listening.IPaddress -eq '0.0.0.0') {
  $LoggingOutput = 'Listening on all IP addresses - ' + $Settings.Server.Listening.IPaddress
  Write-VerboseLog $LoggingOutput
  $IPAddressToUse = [System.Net.IPAddress]::Any
}
else {
  $LoggingOutput = 'Listening on the IP Address - ' + $Settings.Server.Listening.IPaddress
  Write-VerboseLog $LoggingOutput
  $IPAddressToUse = [System.Net.IPAddress]::Parse($Settings.Server.Listening.IPaddress)
}

$MyRunspaceJobs = $null

$MyStatus = [Hashtable]::Synchronized(@{
  Continue = $true
  Emails = @{
    Received = 0
    Sent = 0
    Rejected = 0
    Failed = 0
    SoftFail = 0
  }
})

# *******************************************************
# *******************************************************
# **                                                   **
# **                 FUNCTIONS BLOCK                   **
# **                                                   **
# *******************************************************
# *******************************************************

Function Invoke-EndCleanup {
  If ($MyRunspace) {
    Write-DebugLog 'Closing the MyRunspace'
    $MyRunspace.Close()
    Write-DebugLog 'Disposing the MyRunspace'
    $MyRunspace.Dispose()
  }
  If ($TCPListener) {
    Write-DebugLog 'Stopping the TCPListener'
    $TCPListener.Stop()
  }

  Write-DebugLog 'Doing cleanup tasks (Closing logging file, removing used modules)'
  Close-Logger

  $LoadedModules = Get-Module
  ForEach ($ModuleLoaded in (Compare-Object -ReferenceObject $CurrentModules -DifferenceObject $LoadedModules)) { Remove-Module $ModuleLoaded.InputObject }
  exit
}

Function New-SMTPD {
  param (
    [Parameter(Mandatory)][System.Net.Sockets.TcpClient]$TCPClient
  )
  Write-InformationLog "Incoming connection logged from $($TCPClient.Client.RemoteEndPoint.Address):$($TCPClient.Client.RemoteEndPoint.Port)"

  Write-DebugLog 'Creating new TCP Stream to communicate on'
  $TCPStream = $TCPClient.GetStream()
  $ResponseMSG = "Welcome to " + $Settings.Server.Hostname + ". Running PowerShell SMTP Server version 1.0"
  $TCPStream.Write([System.Text.Encoding]::ASCII.GetBytes($ResponseMSG), 0, $ResponseMSG.Length)

  $Continue = $true
  While ($Continue) {
    if ($TCPStream.DataAvailable) {
      $DataBuffer = $TCPStream.ReadByte()
      if ($DataBuffer -eq 113) {
        $Continue = $false
        $ResponseMSG = "`r`nI am terminating this session.  Bye!`r`n"
      }
      $TCPStream.Write([System.Text.Encoding]::ASCII.GetBytes($ResponseMSG), 0, $ResponseMSG.Length)
    }
  }
  $MyStatus.Continue = $false
}

Function FakeTelnet {
  param (
    [Parameter(Mandatory)][System.Net.Sockets.TcpClient]$TCPClient
  )
  Write-Output "Incoming connection logged from $($TCPClient.Client.RemoteEndPoint.Address):$($TCPClient.Client.RemoteEndPoint.Port)"

  $Stream = $TCPClient.GetStream()
  $Timer = 10; $Ticks = 0; $Continue = $true
  $Response = [System.Text.Encoding]::UTF8.GetBytes("I see you.  I will die in $($Timer.ToString()) seconds.`r`nHit <space> to add another 10 seconds.`r`nType q to quit now.`r`nType x to terminate listener.`r`n`r`n")
  $Stream.Write($Response, 0, $Response.Length)

  $StartTimer = (Get-Date).Ticks
  while (($Timer -gt 0) -and $Continue) {
    if ($Stream.DataAvailable) {
      $Buffer = $Stream.ReadByte()
      Write-Output "Received Data: $($Buffer.ToString())"
      if ($Buffer -eq 113) {
        $Continue = $false
        $Response = [System.Text.Encoding]::UTF8.GetBytes("`r`nI am terminating this session.  Bye!`r`n")
      }
      elseif ($Buffer -eq 32) {
        $Timer += 10
        $Response = [System.Text.Encoding]::UTF8.GetBytes("`r`nAdding another 10 seconds.`r`nI will die in $($Timer.ToString()) seconds.`r`n")
      }
      elseif ($Buffer -eq 120) {
        $Continue = $false
        $Response = [System.Text.Encoding]::UTF8.GetBytes("`r`nI am terminating the listener.  :-(`r`n")
      }
      else { $Response = [System.Text.Encoding]::UTF8.GetBytes("`r`nI see you.  I will die in $($Timer.ToString()) seconds.`r`nHit <space> to add another 10 seconds.`r`nType q to quit this session.`r`nType x to terminate listener.`r`n`r`n") }

      $Stream.Write($Response, 0, $Response.Length)
    }
    $EndTimer = (Get-Date).Ticks
    $Ticks = $EndTimer - $StartTimer
    if ($Ticks -gt 10000000) { $Timer--; $StartTimer = (Get-Date).Ticks }
  }
  $TCPClient.Close()
}

# *******************************************************
# *******************************************************
# **                                                   **
# **            SYSTEM INITIALISATION BLOCK            **
# **                                                   **
# *******************************************************
# *******************************************************

Write-DebugLog 'Attempting to create the IP Endpoint for listening'
$IPEndPoint = try {
  [System.Net.IPEndPoint]::new($IPAddressToUse, $Settings.Server.Listening.Port)
}
catch {
  $LoggingOutput = "An exception was caught... '" + $_.Exception.Message + "'"
  Write-ErrorLog $LoggingOutput
  Write-Error 'Unable to create required IP endpoint. Check logs for more details'
  Write-ErrorLog 'Unable to create required IP endpoint. Check logs for more details'
  
  Invoke-EndCleanup
}

If ($IPEndPoint) {
  Write-DebugLog 'Attempting to create the listener'
  $TCPListener = try {
    [System.Net.Sockets.TcpListener]::new($IPEndPoint)
  }
  catch {
    $LoggingOutput = "An exception was caught... '" + $_.Exception.Message + "'"
    Write-ErrorLog $LoggingOutput
    Write-Error 'Unable to create required listener. Check logs for more details'
    Write-ErrorLog 'Unable to create required listener. Check logs for more details'
    
    Invoke-EndCleanup
  }
}

Write-DebugLog 'Successfully created the listener & IP Endpoint'


$LoggingOutput = 'Initialising the new Runspace'
Write-DebugLog $LoggingOutput

$MyRunspaceInitialisation = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
$MyRunspaceInitialisation.Variables.Add((New-Object -TypeName System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'MyStatus', $MyStatus, ''))

$LoggingOutput = 'Attempting to open a Runspace pool with a max of ' + [uint32]$Settings.Server.MaxThreads + " threads"
Write-DebugLog $LoggingOutput
$MyRunspace = try {
  [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, [uint32]$Settings.Server.MaxThreads, $MyRunspaceInitialisation, $Host)
}
catch {
  $LoggingOutput = "An exception was caught... '" + $_.Exception.Message + "'"
  Write-ErrorLog $LoggingOutput
  Write-Error 'Unable to create required the Runspace pool. Check logs for more details'
  Write-ErrorLog 'Unable to create required the Runspace pool. Check logs for more details'
  
  Invoke-EndCleanup
}

try {
  $MyRunspace.Open() 
}
catch {
  $LoggingOutput = "An exception was caught... '" + $_.Exception.Message + "'"
  Write-ErrorLog $LoggingOutput
  Write-Error 'Unable to open the Runspace pool. Check logs for more details'
  Write-ErrorLog 'Unable to open the Runspace pool. Check logs for more details'
  
  Invoke-EndCleanup
}
Write-DebugLog 'Successfully created the Runspace pool & opened it.'

# *******************************************************
# *******************************************************
# **                                                   **
# **                  MAIN CODE BLOCK                  **
# **                                                   **
# *******************************************************
# *******************************************************

Write-VerboseLog 'Starting the listener'
$TCPListener.Start()

$KeepListening = $true
while ($KeepListening) {
  while (!$TCPListener.Pending) {Write-VerboseLog 'Waiting 100ms'; Start-Sleep -Milliseconds 100}

  #FakeTelnet -TCPClient $TCPListener.AcceptTcpClient()
  Write-DebugLog 'Creating a PowerShell instance'
  $NewRunspaceJob = [powershell]::Create()
  $NewRunspaceJob.RunspacePool = $MyRunspace
  $NewRunspaceJob.AddScript({New-SMTPD}).AddParameter("TCPClient", $TCPListener.AcceptTcpClient())
  $MyRunspaceJobs += $NewRunspaceJob
  Write-DebugLog 'Invoking PowerShell instance'
  $NewRunspaceJob.BeginInvoke()
}


# *******************************************************
# *******************************************************
# **                                                   **
# **                CLEAN UP CODE BLOCK                **
# **                                                   **
# *******************************************************
# *******************************************************

Invoke-EndCleanup
