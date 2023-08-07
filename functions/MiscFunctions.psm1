
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

Function Show-StringCharacters{
    <#
    .SYNOPSIS
        Takes a string and converts it into invdividual characters & the values.
    .DESCRIPTION
        Converts the supplied string into a character array, and then displays an output of each character and its value. The output is sent to the console host.
    .PARAMETER String
        [System.String]
        The string to work and show the individual characters and values.
    .EXAMPLE
        C:\PS> Show-StringCharacters -String 'This is a test'
        This character is [T] its value is [84]
        This character is [h] its value is [104]
        This character is [i] its value is [105]
        This character is [s] its value is [115]
        This character is [ ] its value is [32]
        This character is [i] its value is [105]
        This character is [s] its value is [115]
        This character is [ ] its value is [32]
        This character is [a] its value is [97]
        This character is [ ] its value is [32]
        This character is [t] its value is [116]
        This character is [e] its value is [101]
        This character is [s] its value is [115]
        This character is [t] its value is [116]
    .INPUTS
        System.String
        You can pipe a string that contains a path to Get-VSCodeSnippet.
    .NOTES
        This is more for testing than being useful.
    #>
    
    [CmdletBinding()]
    param(
      [Parameter(Mandatory=$true,
                ValueFromPipeline=$true,
                HelpMessage='The string to display as individual characters & value.')]
      [ValidateNotNullOrEmpty]
      $String
    )
    $TempChars = $String.ToCharArray()
    Foreach ($Character in $TempChars){
      $LoggingOutput = "This This character is [[" + $Character + "] its value is [" + [Int32]$Character + "]"
      Write-Host $LoggingOutput
    }
  }