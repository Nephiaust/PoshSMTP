
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


Function Invoke-SMTPD_EHLO {
    <#
    .SYNOPSIS
        Takes the EHLO command and greets the client.
    .DESCRIPTION
        Takes the EHLO command and greets the client, before allowing normal EHLO operations.
    .PARAMETER UserCommand
        [System.String]
        Takes the inputted command from the user.
    .NOTES
        TODO, needs more work.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = 'The full command entered by the client')]
        [String]$UserCommand,

        [Parameter(Mandatory = $true, HelpMessage = 'The inbound TCP Data Stream from the client')]
        [System.Net.Sockets.NetworkStream]$DataStream
    )
    Write-VerboseLog 'Received a EHLO command.'
    if ($UserCommand.length -lt 5) {
        Write-VerboseLog 'EHLO command was invalid'
        $ResponseMSG = "550 Requested action not taken: Syntax error`r`n"
        $DataStream.Write([System.Text.Encoding]::ASCII.GetBytes($ResponseMSG), 0, $ResponseMSG.Length)
    }
    else {
        $ClientHost = $UserCommand.Substring(5, ($UserCommand.Length - 5))
        $AppDetails.MaxSize = $Settings.Server.MaxSizeKB.ToInt32($null) * 1024
        $ResponseMSG = "250-" + $Settings.Server.Hostname + " welcomes " + $ClientHost + "`r`n"
        # If the max size has been set, tell the client what it is.
        If ($Settings.Server.MaxSizeKB.ToInt32($null) -gt 0) { $ResponseMSG += "250-SIZE " + $AppDetails.MaxSize + "`r`n" }
        $ResponseMSG += "250 HELP`r`n"
        $DataStream.Write([System.Text.Encoding]::ASCII.GetBytes($ResponseMSG), 0, $ResponseMSG.Length)
    }
}
