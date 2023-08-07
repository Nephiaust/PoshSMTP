#Requires -Version 5.1
#Requires -Modules PoShLog

$Settings = ([xml](Get-Content ./config.xml)).configuration
$AppDetails = @{
  Name = "PoshSMTP"
  Version = "1.0.0"
}

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

Function Invoke-SMTPD_NOOP {
  param (
    [Parameter(Mandatory)][string]$UserCommand
  )
  Write-VerboseLog 'Received a NOOP command. Doing nothing'
  if ($UserCommand.Length -gt 5) {
    $ResponseMSG = "250 Okay, not doing '" + $UserCommand.Substring(5,($UserCommand.Length - 5)) + "'`r`n"
    $TCPStream.Write([System.Text.Encoding]::ASCII.GetBytes($ResponseMSG), 0, $ResponseMSG.Length)
  } else {
    $ResponseMSG = "250 Okay, doing nothing`r`n"
    $TCPStream.Write([System.Text.Encoding]::ASCII.GetBytes($ResponseMSG), 0, $ResponseMSG.Length)
  }
}

Function Invoke-SMTPD_RSET {
  param (
    [Switch]$Full
  )
  Write-VerboseLog 'Received a RSET command. Doing nothing'
  if ($UserInput.length -gt 4){
    Write-VerboseLog 'RSET command was invalid'
    $ResponseMSG = "500 Syntax error, command unrecognized`r`n"
    $TCPStream.Write([System.Text.Encoding]::ASCII.GetBytes($ResponseMSG), 0, $ResponseMSG.Length)
  } else {
    $ResponseMSG = "250 OK`r`n"
    $TCPStream.Write([System.Text.Encoding]::ASCII.GetBytes($ResponseMSG), 0, $ResponseMSG.Length)
  }
  If ($Full) {Invoke-SMTPD_Start}
}

Function Invoke-SMTPD_QUIT {
  param (
    [Parameter(Mandatory)][string]$UserCommand
  )
  Write-VerboseLog 'Received a QUIT command. Quiting session with client'
  if ($UserInput.length -gt 4){
    Write-VerboseLog 'QUIT command was invalid'
    $ResponseMSG = "500 Syntax error, command unrecognized`r`n"
    $TCPStream.Write([System.Text.Encoding]::ASCII.GetBytes($ResponseMSG), 0, $ResponseMSG.Length)
  } else {
    $ResponseMSG = "221 OK`r`n"
    $TCPStream.Write([System.Text.Encoding]::ASCII.GetBytes($ResponseMSG), 0, $ResponseMSG.Length)
  }
}

Function Invoke-SMTPD_HELO {
  param (
    [Parameter(Mandatory)][string]$UserCommand
  )
  Write-VerboseLog 'Received a HELO command.'
  if ($UserInput.length -lt 5){
    Write-VerboseLog 'HELO command was invalid'
    $ResponseMSG = "501 Requested action not taken: Syntax error`r`n"
    $TCPStream.Write([System.Text.Encoding]::ASCII.GetBytes($ResponseMSG), 0, $ResponseMSG.Length)
  } else {
    $ResponseMSG = "250 Welcome " + $UserCommand.Substring(5,($UserCommand.Length - 5)) + ". I am ready`r`n"
    $TCPStream.Write([System.Text.Encoding]::ASCII.GetBytes($ResponseMSG), 0, $ResponseMSG.Length)
  }
}

Function Invoke-SMTPD_EHLO {
  param (
    [Parameter(Mandatory)][string]$UserCommand
  )
  Write-VerboseLog 'Received a EHLO command.'
  if ($UserInput.length -lt 5){
    Write-VerboseLog 'EHLO command was invalid'
    $ResponseMSG = "550 Requested action not taken: Syntax error`r`n"
    $TCPStream.Write([System.Text.Encoding]::ASCII.GetBytes($ResponseMSG), 0, $ResponseMSG.Length)
  } else {
    $ResponseMSG  = "250-" + $Settings.Server.Hostname +" welcomes " + $UserCommand.Substring(5,($UserCommand.Length - 5)) + "`r`n"
    # If the max size has been set, tell the client what it is.
    If ($Settings.Server.MaxSizeKB.ToInt32($null) -gt 0) {$ResponseMSG += "250-SIZE " + ($Settings.Server.MaxSizeKB.ToInt32($null) * 1024) + "`r`n"}
    $ResponseMSG += "250 HELP`r`n"
    $TCPStream.Write([System.Text.Encoding]::ASCII.GetBytes($ResponseMSG), 0, $ResponseMSG.Length)
  }
}

Function Invoke-SMTPD_VRFY {
  param (
    [Parameter(Mandatory)][string]$UserCommand
  )
  Write-VerboseLog 'Received a VRFY command.'
  if ($UserInput.length -lt 5){
    Write-VerboseLog 'VRFY command was invalid'
    $ResponseMSG = "550 Requested action not taken: Syntax error`r`n"
    $TCPStream.Write([System.Text.Encoding]::ASCII.GetBytes($ResponseMSG), 0, $ResponseMSG.Length)
  } else {
    $ResponseMSG = "502 Command not implemented yet`r`n"
    $TCPStream.Write([System.Text.Encoding]::ASCII.GetBytes($ResponseMSG), 0, $ResponseMSG.Length)
  }
}

Function Invoke-SMTPD_EXPN {
  param (
    [Parameter(Mandatory)][string]$UserCommand
  )
  Write-VerboseLog 'Received a EXPN command.'
  if ($UserInput.length -lt 5){
    Write-VerboseLog 'EXPN command was invalid'
    $ResponseMSG = "550 Requested action not taken: Syntax error`r`n"
    $TCPStream.Write([System.Text.Encoding]::ASCII.GetBytes($ResponseMSG), 0, $ResponseMSG.Length)
  } else {
    $ResponseMSG = "502 Command not implemented yet`r`n"
    $TCPStream.Write([System.Text.Encoding]::ASCII.GetBytes($ResponseMSG), 0, $ResponseMSG.Length)
  }
}

Function Close-SMTP {
  $TCPClient.Close()
  $MyStatus.Continue = $false
}

Function New-SMTPD {
  param (
    [Parameter(Mandatory)][System.Net.Sockets.TcpClient]$TCPClient
  )
  Write-InformationLog "Incoming connection logged from $($TCPClient.Client.RemoteEndPoint.Address):$($TCPClient.Client.RemoteEndPoint.Port)"

  Write-DebugLog 'Creating new TCP Stream to communicate on'
  $TCPStream = $TCPClient.GetStream()
  $ResponseMSG = "220-Welcome to " + $Settings.Server.Hostname + ".`r`n"
  $ResponseMSG += "220 Running " + $AppDetails.Name + " ver: " + $AppDetails.Version + "`r`n"
  $TCPStream.Write([System.Text.Encoding]::ASCII.GetBytes($ResponseMSG), 0, $ResponseMSG.Length)
  Invoke-SMTPD_Start
  Close-SMTP
}
Function Invoke-SMTPD_Start {
  $Continue = $true
  While ($Continue) {
    [String]$UserInput = $null
    while (!$TCPStream.DataAvailable) {
      Start-Sleep -Milliseconds 100
    }
    if ($TCPStream.DataAvailable) {
      $ReceivingData = $true
      While ($ReceivingData){
        $Inoput = $TCPStream.ReadByte()
        switch ($Inoput){
          13 {break}
          10 {$ReceivingData=$false;break}
          default {$UserInput += [char]$Inoput;break}
        }
      }
    }
    # Cleaning up the input to remove any trailing spaces.
    $UserInput = $UserInput.TrimEnd()

    # Verifying that the input is 4 or more characters
    if ($UserInput.Length -gt 3) {
      Switch ($UserInput.substring(0,4)){
        "help" {
          Write-VerboseLog 'Received a HELP command. Sending help'
          $ResponseMSG  = "200-Available commands in this context EHLO, EXPN, HELO, HELP, NOOP, QUIT, RSET, VRFY`r`n"
          $ResponseMSG += "200 Not available commands DATA, MAIL, RCPT`r`n"
          $TCPStream.Write([System.Text.Encoding]::ASCII.GetBytes($ResponseMSG), 0, $ResponseMSG.Length)
          break
        }
        
        # QUIT must be by itself. RFC5321 says its SHOULD be, but we are being stupid about it.
        "quit" {Invoke-SMTPD_QUIT -Usercommand $UserInput;$Continue = $false;break}
        
        # RSET must be by itself. RFC5321 says its SHOULD be, but we are being stupid about it.
        "rset" {Invoke-SMTPD_RSET -Usercommand $UserInput;break}

        # Do nothing
        "noop" {Invoke-SMTPD_NOOP -Usercommand $UserInput;break}

        # Do the old school HELO SMTP
        "helo" {Invoke-SMTPD_HELO -Usercommand $UserInput;break}

        # Do the new school EHLO SMTP
        "ehlo" {Invoke-SMTPD_EHLO -Usercommand $UserInput;break}

        # Verify the data the client sent us
        "vrfy" {Invoke-SMTPD_VRFY -Usercommand $UserInput;break}
        
        # Do something about expanding.
        "expn" {Invoke-SMTPD_EXPN -Usercommand $UserInput;break}
        
        # Everything is a bad syntax / command. Naughty naughty.
        default {Write-VerboseLog 'Received a invalid command. Sending error';$ResponseMSG = "501 Syntax error, command unrecognized`r`n";$TCPStream.Write([System.Text.Encoding]::ASCII.GetBytes($ResponseMSG), 0, $ResponseMSG.Length);break}
      }
    } else {
      # Why were we given an input thats less than 4 characters in length? WHYYYY
      Write-VerboseLog 'Received a invalid command (less than 4 characters in length). Sending error'
      $ResponseMSG = "500 Syntax error, command unrecognized`r`n";$TCPStream.Write([System.Text.Encoding]::ASCII.GetBytes($ResponseMSG), 0, $ResponseMSG.Length)
    }
  }
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

If ($true){
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
  $MyRunspaceInitialisation.Variables.Add((New-Object -TypeName System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'LogSettings', $Settings.Logging, ''))

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
}

# *******************************************************
# *******************************************************
# **                                                   **
# **                  MAIN CODE BLOCK                  **
# **                                                   **
# *******************************************************
# *******************************************************

Write-VerboseLog 'Starting the listener'
$TCPListener.Start()

while ($MyStatus.Continue) {
  Write-VerboseLog 'Polling every 100ms to see if another connection come in'
  while (!$TCPListener.Pending()) {
    Start-Sleep -Milliseconds 100
  }

  #FakeTelnet -TCPClient $TCPListener.AcceptTcpClient()
  # Write-VerboseLog 'Creating a PowerShell instance'
  # $NewRunspaceJob = [powershell]::Create()
  # Write-VerboseLog ' * Setting the runspace'
  # $NewRunspaceJob.RunspacePool = $MyRunspace
  # Write-VerboseLog ' * Adding the script'
  # [void] $NewRunspaceJob.AddScript({New-SMTPD}).AddParameter("TCPClient", $TCPListener.AcceptTcpClient())
  # Write-VerboseLog ' * Saving the details to the Job Tracker'
  # $MyRunspaceJobs += $NewRunspaceJob
  # Write-VerboseLog 'Invoking PowerShell instance'
  # [void] $NewRunspaceJob.BeginInvoke()
  New-SMTPD -TCPClient $TCPListener.AcceptTcpClient()
}


# *******************************************************
# *******************************************************
# **                                                   **
# **                CLEAN UP CODE BLOCK                **
# **                                                   **
# *******************************************************
# *******************************************************

Invoke-EndCleanup
