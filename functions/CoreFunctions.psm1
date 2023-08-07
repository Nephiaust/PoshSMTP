
# *******************************************************
# *******************************************************
# **                                                   **
# **            DO NOT EDIT BELOW THIS BLOCK           **
# **                                                   **
# **                INITIALISATION BLOCK               **
# **                                                   **
# *******************************************************
# *******************************************************


# *******************************************************
# *******************************************************
# **                                                   **
# **              INTERNAL VARIABLES BLOCK             **
# **                                                   **
# *******************************************************
# *******************************************************


# *******************************************************
# *******************************************************
# **                                                   **
# **                 FUNCTIONS BLOCK                   **
# **                                                   **
# *******************************************************
# *******************************************************


# *******************************************************
# *******************************************************
# **                                                   **
# **            SYSTEM INITIALISATION BLOCK            **
# **                                                   **
# *******************************************************
# *******************************************************


# *******************************************************
# *******************************************************
# **                                                   **
# **                  MAIN CODE BLOCK                  **
# **                                                   **
# *******************************************************
# *******************************************************

Function New-SMTPD {
    <#
    .SYNOPSIS
        Starts the process of receiving mail from a TCP Client conneciton
    .DESCRIPTION
        Starts the process of receiving mail from a TCP Client conneciton
    .PARAMETER TCPClient
        [System.Net.Sockets.TcpClient]
        Takes the new TCP Client connection
    .NOTES
        This function is a simple one to do the welcome and set up of the new inbound connection
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,HelpMessage='The inbound TCP Client Connection from the client')][System.Net.Sockets.TcpClient]$TCPClient
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
    <#
    .SYNOPSIS
        The initial 'menu' system for SMTPD. Implements basic checking of inputs and calls functions as required.
    .DESCRIPTION
        The initial 'menu' system for SMTPD. Implements basic checking of inputs and calls functions as required.
    .NOTES
        Was easier to have it here, instead of the New-SMTPD function.
    #>
    $Continue = $true
    While ($Continue) {
        [String]$UserInput = $null

        # Checks for any data available, if not waits 100ms before checking again
        while (!$TCPStream.DataAvailable) {
            Start-Sleep -Milliseconds 100
        }

        if ($TCPStream.DataAvailable) {
            # Needs to receive the CR and LF line terminators
            $ReceivedCRLF = 0
            While ($ReceivedCRLF -ne 2) {
                $UserCharInput = $TCPStream.ReadByte()
                switch ($UserCharInput) {
                    10 { $ReceivedCRLF++; break }
                    13 { $ReceivedCRLF++; break }
                    default { $UserInput += [char]$UserCharInput; break }
                }
            }
        }

        # Cleaning up the input to remove any trailing spaces.
        $UserInput = $UserInput.TrimEnd()
  
        # Verifying that the input is 4 or more characters
        if ($UserInput.Length -gt 3) {
            Switch ($UserInput.substring(0, 4)) {
                "help" {
                    Write-VerboseLog 'Received a HELP command. Sending help'
                    $ResponseMSG  = "200-Available commands in this context EHLO, EXPN, HELO, HELP, NOOP, QUIT, RSET, VRFY`r`n"
                    $ResponseMSG += "200 Commands not avialable in this context DATA, MAIL, RCPT`r`n"
                    $TCPStream.Write([System.Text.Encoding]::ASCII.GetBytes($ResponseMSG), 0, $ResponseMSG.Length)
                    break
                }
                "quit" { Invoke-SMTPD_QUIT -Usercommand $UserInput; $Continue = $false; break }
                "rset" { Invoke-SMTPD_RSET -Usercommand $UserInput; break }
                "noop" { Invoke-SMTPD_NOOP -Usercommand $UserInput; break }
                "helo" {
                    if ($UserInput.length -lt 5) {
                        Write-VerboseLog 'HELO command was invalid'
                        $ResponseMSG = "501 Requested action not taken: Syntax error`r`n"
                        $TCPStream.Write([System.Text.Encoding]::ASCII.GetBytes($ResponseMSG), 0, $ResponseMSG.Length)
                    } else {
                        Invoke-SMTPD_HELO -Usercommand $UserInput -DataStream $TCPStream
                    }
                    break
                }
                "ehlo" {
                    if ($UserInput.length -lt 5) {
                        Write-VerboseLog 'EHLO command was invalid'
                        $ResponseMSG = "501 Requested action not taken: Syntax error`r`n"
                        $TCPStream.Write([System.Text.Encoding]::ASCII.GetBytes($ResponseMSG), 0, $ResponseMSG.Length)
                    } else {
                        Invoke-SMTPD_EHLO -Usercommand $UserInput -DataStream $TCPStream
                    }
                    break
                }
                "vrfy" { Invoke-SMTPD_VRFY -Usercommand $UserInput; break }
                "expn" { Invoke-SMTPD_EXPN -Usercommand $UserInput; break }
          
                # Everything is a bad syntax / command. Naughty naughty.
                default { Write-VerboseLog 'Received a invalid command. Sending error'; $ResponseMSG = "501 Syntax error, command unrecognized`r`n"; $TCPStream.Write([System.Text.Encoding]::ASCII.GetBytes($ResponseMSG), 0, $ResponseMSG.Length); break }
            }
        } else {
            # Why were we given an input thats less than 4 characters in length? WHYYYY
            Write-VerboseLog 'Received a invalid command (less than 4 characters in length). Sending error'
            $ResponseMSG = "500 Syntax error, command unrecognized`r`n"; $TCPStream.Write([System.Text.Encoding]::ASCII.GetBytes($ResponseMSG), 0, $ResponseMSG.Length)
        }
    }
}
  

Function Invoke-SMTPD_VRFY {
    <#
    .SYNOPSIS
        TODO, responds with an error of not implemented.
    .DESCRIPTION
        TODO, responds with an error of not implemented.
    .NOTES
        TODO, responds with an error of not implemented.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,HelpMessage='The full command entered by the client')][String]$UserCommand
    )
    Write-VerboseLog 'VRFY command was invalid'
    $ResponseMSG = "502 Command not implemented yet`r`n"
    $TCPStream.Write([System.Text.Encoding]::ASCII.GetBytes($ResponseMSG), 0, $ResponseMSG.Length)
}
  
Function Invoke-SMTPD_EXPN {
    <#
    .SYNOPSIS
        TODO, responds with an error of not implemented.
    .DESCRIPTION
        TODO, responds with an error of not implemented.
    .NOTES
        TODO, responds with an error of not implemented.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,HelpMessage='The full command entered by the client')][String]$UserCommand
    )
    Write-VerboseLog 'Received a EXPN command.'
    $ResponseMSG = "502 Command not implemented yet`r`n"
    $TCPStream.Write([System.Text.Encoding]::ASCII.GetBytes($ResponseMSG), 0, $ResponseMSG.Length)
}
  
Function Close-SMTP {
    <#
    .SYNOPSIS
        Closes the existing SMTP client connection. 
    .DESCRIPTION
        Closes the existing SMTP client connection.
    .NOTES
        Was created as it was been called from different ways.
    #>
    $TCPClient.Close()
    $MyStatus.Continue = $false
}

Function Invoke-SMTPD_RSET {
    <#
    .SYNOPSIS
        Takes the RSET command and resets the current context, deleting/reseting any submitted settings (e.g. from, to, data). 
    .DESCRIPTION
        Takes the RSET command (and any parameters, if there are any throw an unrecognised error back to client).
        If doing a basic reset just respond back with 250 OK, if doing a full reset clear any pending settings (e.g. from, to, data).
    .PARAMETER UserCommand
        [System.Switch]
        Does a full reset of the current context need to occur?
    #>
    [CmdletBinding()]
    param (
        [Parameter(HelpMessage='Is this a full reset, so all current client commands are cleared.')][Switch]$Full,
        [Parameter(Mandatory=$true,HelpMessage='The full command entered by the client')][String]$UserCommand
    )
    Write-VerboseLog 'Received a RSET command. Doing nothing'
    if ($UserCommand.length -gt 4) {
        Write-VerboseLog 'RSET command was invalid'
        $ResponseMSG = "500 Syntax error, command unrecognized`r`n"
        $TCPStream.Write([System.Text.Encoding]::ASCII.GetBytes($ResponseMSG), 0, $ResponseMSG.Length)
    }
    else {
        $ResponseMSG = "250 OK`r`n"
        $TCPStream.Write([System.Text.Encoding]::ASCII.GetBytes($ResponseMSG), 0, $ResponseMSG.Length)
    }
    If ($Full) { Invoke-SMTPD_Start }
}
  
Function Invoke-SMTPD_QUIT {
    <#
    .SYNOPSIS
        Takes the QUIT command and repsonds with a 221 OK response.
    .DESCRIPTION
        Takes the QUIT command (and any parameters, if there are any throw an unrecognised error back to client). Repsonds with a 221 response when successfully quiting
    .PARAMETER UserCommand
        [System.String]
        Takes the inputted command from the user.
    .NOTES
        QUIT must be by itself. RFC5321 says its SHOULD be, but we are being stupid about it.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,HelpMessage='The full command entered by the client')][String]$UserCommand
    )
    Write-VerboseLog 'Received a QUIT command. Quiting session with client'
    if ($UserCommand.length -gt 4) {
        Write-VerboseLog 'QUIT command was invalid'
        $ResponseMSG = "500 Syntax error, command unrecognized`r`n"
        $TCPStream.Write([System.Text.Encoding]::ASCII.GetBytes($ResponseMSG), 0, $ResponseMSG.Length)
    }
    else {
        $ResponseMSG = "221 OK`r`n"
        $TCPStream.Write([System.Text.Encoding]::ASCII.GetBytes($ResponseMSG), 0, $ResponseMSG.Length)
    }
}


Function Invoke-SMTPD_NOOP {
    <#
    .SYNOPSIS
        Takes the NOOP command and repsonds with a 250 OK response.
    .DESCRIPTION
        Takes the NOOP command (and any parameters). Repsonds with a 250 response to do nothing
    .PARAMETER UserCommand
        [System.String]
        Takes the inputted command from the user.
    .NOTES
        NOOP must be by itself. RFC5321 says its SHOULD be, but we are being stupid about it.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,HelpMessage='The full command entered by the client')][String]$UserCommand
    )
    Write-VerboseLog 'Received a NOOP command. Doing nothing'
    if ($UserCommand.Length -gt 5) {
        $ResponseMSG = "250 Okay, not doing '" + $UserCommand.Substring(5, ($UserCommand.Length - 5)) + "'`r`n"
        $TCPStream.Write([System.Text.Encoding]::ASCII.GetBytes($ResponseMSG), 0, $ResponseMSG.Length)
    }
    else {
        $ResponseMSG = "250 Okay, doing nothing`r`n"
        $TCPStream.Write([System.Text.Encoding]::ASCII.GetBytes($ResponseMSG), 0, $ResponseMSG.Length)
    }
}
  