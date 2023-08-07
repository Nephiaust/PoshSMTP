
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
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            HelpMessage = 'The full command entered by the client')]
        [ValidateNotNullOrEmpty]
        [String]
        $UserCommand
    )
    Write-VerboseLog 'Received a HELO command.'
    if ($UserInput.length -lt 5) {
        Write-VerboseLog 'HELO command was invalid'
        $ResponseMSG = "501 Requested action not taken: Syntax error`r`n"
        $TCPStream.Write([System.Text.Encoding]::ASCII.GetBytes($ResponseMSG), 0, $ResponseMSG.Length)
    }
    else {
        $ResponseMSG = "250 Welcome " + $UserCommand.Substring(5, ($UserCommand.Length - 5)) + ". I am ready`r`n"
        $TCPStream.Write([System.Text.Encoding]::ASCII.GetBytes($ResponseMSG), 0, $ResponseMSG.Length)
    }
}