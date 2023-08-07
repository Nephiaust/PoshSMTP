
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


Function Invoke-SMTPD_HELO {
    <#
    .SYNOPSIS
        Takes the HELO command and greets the client.
    .DESCRIPTION
        Takes the HELO command and greets the client, before allowing normal HELO operations.
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
    Write-VerboseLog 'Received a HELO command.'
    if ($UserCommand.length -lt 5) {
        Write-VerboseLog 'HELO command was invalid'
        $ResponseMSG = "501 Requested action not taken: Syntax error`r`n"
        $DataStream.Write([System.Text.Encoding]::ASCII.GetBytes($ResponseMSG), 0, $ResponseMSG.Length)
    }
    else {
        $ClientHost = $UserCommand.Substring(5, ($UserCommand.Length - 5))
        $ResponseMSG = "250 Welcome " + $ClientHost + ". I am ready`r`n"
        $DataStream.Write([System.Text.Encoding]::ASCII.GetBytes($ResponseMSG), 0, $ResponseMSG.Length)
    }
}