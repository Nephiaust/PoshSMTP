
$PackageDetection = try {
    Get-Package -Name Microsoft.Data.Sqlite.Core -AllVersions | Out-Null
}
Catch {Write-Error $_}

If (!$PackageDetection) {
    Install-Package -MinimumVersion 7.0.8 -Name Microsoft.Data.Sqlite.Core -Providername NuGet -Force -Scope CurrentUser
}


Write-DebugLog 'Loading the SQLite Assembly'
[Reflection.Assembly]::LoadFile($SQLiteAssembly)

Function New-PoshSQLiteConnection {
    [cmdletbinding()]
    [OutputType([System.Data.SQLite.SQLiteConnection])]
    param (
        [Parameter(Mandatory = $true, HelpMessage = 'The SQLite database location')]
        [String]$Database,

        [Parameter(HelpMessage = 'The SecureString password for the database')]
        [System.Security.SecureString]$Password,

        [Parameter(HelpMessage = 'Is the Database being opened as READ ONLY')]
        [Switch]$ReadOnly
    )

    Begin {
        $SQLiteConnectionString ="Data Source=" + $Database + ";"
        if ($ReadOnly) { $SQLiteConnectionString += "Read Only=True;"}
        if ($Password) {
            $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
            $PlainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            $SQLiteConnectionString += "Password=$PlainPassword;"
        }
    }

    Process {
        $MySQLiteConnection = New-Object System.Data.SQLite.SQLiteConnection
        $MySQLiteConnection.ConnectionString = $SQLiteConnectionString

        try {
            $MySQLiteConnection.open()
        }
        catch {
            Write-Error $_
            Throw $_
        }
    }
}