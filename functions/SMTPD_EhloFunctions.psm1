
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
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            HelpMessage = 'The full command entered by the client')]
        [ValidateNotNullOrEmpty]
        [String]
        $UserCommand
    )
    Write-VerboseLog 'Received a EHLO command.'
    if ($UserInput.length -lt 5) {
        Write-VerboseLog 'EHLO command was invalid'
        $ResponseMSG = "550 Requested action not taken: Syntax error`r`n"
        $TCPStream.Write([System.Text.Encoding]::ASCII.GetBytes($ResponseMSG), 0, $ResponseMSG.Length)
    }
    else {
        $ResponseMSG = "250-" + $Settings.Server.Hostname + " welcomes " + $UserCommand.Substring(5, ($UserCommand.Length - 5)) + "`r`n"
        # If the max size has been set, tell the client what it is.
        If ($Settings.Server.MaxSizeKB.ToInt32($null) -gt 0) { $ResponseMSG += "250-SIZE " + ($Settings.Server.MaxSizeKB.ToInt32($null) * 1024) + "`r`n" }
        $ResponseMSG += "250 HELP`r`n"
        $TCPStream.Write([System.Text.Encoding]::ASCII.GetBytes($ResponseMSG), 0, $ResponseMSG.Length)
    }
}
