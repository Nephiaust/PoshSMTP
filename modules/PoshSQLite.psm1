if (-not $PSScriptRoot) {
    $MyPSScriptRoot = Split-Path $MyInvocation.MyCommand.Path -Parent
}

$AssemblyLocation = Join-path $MyPSScriptRoot "PoshSQLite\System.Data.SQLite.dll"

Write-DebugLog 'Loading the SQLite Assembly'
[Reflection.Assembly]::LoadFile($AssemblyLocation)

Function New-SQLiteConnection {
    <#
    .SYNOPSIS
        Creates a SQLiteConnection to a SQLite data source
    
    .DESCRIPTION
        Creates a SQLiteConnection to a SQLite data source
    
    .PARAMETER DataSource
       SQLite Data Source to connect to.
    
    .PARAMETER Password
        Specifies A Secure String password to use in the SQLite connection string.
                
        SECURITY NOTE: If you use the -Debug switch, the connectionstring including plain text password will be sent to the debug stream.
    
    .PARAMETER ReadOnly
        If specified, open SQLite data source as read only

    .PARAMETER Open
        We open the connection by default.  You can use this parameter to create a connection without opening it.

    .OUTPUTS
        System.Data.SQLite.SQLiteConnection

    .EXAMPLE
        $Connection = New-SQLiteConnection -DataSource C:\NAMES.SQLite
        Invoke-SQLiteQuery -SQLiteConnection $Connection -query $Query

        # Connect to C:\NAMES.SQLite, invoke a query against it

    .EXAMPLE
        $Connection = New-SQLiteConnection -DataSource :MEMORY: 
        Invoke-SqliteQuery -SQLiteConnection $Connection -Query "CREATE TABLE OrdersToNames (OrderID INT PRIMARY KEY, fullname TEXT);"
        Invoke-SqliteQuery -SQLiteConnection $Connection -Query "INSERT INTO OrdersToNames (OrderID, fullname) VALUES (1,'Cookie Monster');"
        Invoke-SqliteQuery -SQLiteConnection $Connection -Query "PRAGMA STATS"

        # Create a connection to a SQLite data source in memory
        # Create a table in the memory based datasource, verify it exists with PRAGMA STATS

        $Connection.Close()
        $Connection.Open()
        Invoke-SqliteQuery -SQLiteConnection $Connection -Query "PRAGMA STATS"

        #Close the connection, open it back up, verify that the ephemeral data no longer exists

    .LINK
        https://github.com/RamblingCookieMonster/Invoke-SQLiteQuery

    .LINK
        Invoke-SQLiteQuery

    .FUNCTIONALITY
        SQL

    #>
    [cmdletbinding()]
    [OutputType([System.Data.SQLite.SQLiteConnection])]
    param(
        [Parameter( Position = 0,
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false,
            HelpMessage = 'SQL Server Instance required...' )]
        [Alias( 'Instance', 'Instances', 'ServerInstance', 'Server', 'Servers', 'cn', 'Path', 'File', 'FullName', 'Database' )]
        [ValidateNotNullOrEmpty()][string[]]$DataSource,
                
        [Parameter( Position = 2,
            Mandatory = $false,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false )]
        [System.Security.SecureString]$Password,

        [Parameter( Position = 3,
            Mandatory = $false,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false )]
        [Switch]$ReadOnly,

        [Parameter( Position = 4,
            Mandatory = $false,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false )]
        [bool]$Open = $True
    )
    Process {
        foreach ($DataSRC in $DataSource) {
            if ($DataSRC -match ':MEMORY:' ) { $Database = $DataSRC } else { $Database = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DataSRC) }
            
            Write-Verbose "Querying Data Source '$Database'"
            [string]$ConnectionString = "Data Source=$Database;"
            if ($Password) {
                $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
                $PlainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
                $ConnectionString += "Password=$PlainPassword;"
            }

            if ($ReadOnly) { $ConnectionString += "Read Only=True;" }
        
            $conn = New-Object System.Data.SQLite.SQLiteConnection -ArgumentList $ConnectionString
            $conn.ParseViaFramework = $true #Allow UNC paths, thanks to Ray Alex!
            Write-Debug "ConnectionString $ConnectionString"

            if ($Open) { Try { $conn.Open() } Catch { Write-Error $_; continue } }
            write-Verbose "Created SQLiteConnection:`n$($Conn | Out-String)"
            $Conn
        }
    }
}

function Invoke-SqliteQuery {  
    <# 
    .SYNOPSIS 
        Runs a SQL script against a SQLite database.

    .DESCRIPTION 
        Runs a SQL script against a SQLite database.
        Paramaterized queries are supported. 
        Help details below borrowed from Invoke-Sqlcmd, may be inaccurate here.

    .PARAMETER DataSource
        Path to one or more SQLite data sources to query 

    .PARAMETER Query
        Specifies a query to be run.

    .PARAMETER InputFile
        Specifies a file to be used as the query input to Invoke-SqliteQuery. Specify the full path to the file.

    .PARAMETER QueryTimeout
        Specifies the number of seconds before the queries time out.

    .PARAMETER As
        Specifies output type - DataSet, DataTable, array of DataRow, PSObject or Single Value 
        PSObject output introduces overhead but adds flexibility for working with results: http://powershell.org/wp/forums/topic/dealing-with-dbnull/

    .PARAMETER SqlParameters
        Hashtable of parameters for parameterized SQL queries.  http://blog.codinghorror.com/give-me-parameterized-sql-or-give-me-death/

        Limited support for conversions to SQLite friendly formats is supported.
            For example, if you pass in a .NET DateTime, we convert it to a string that SQLite will recognize as a datetime

        Example:
            -Query "SELECT ServerName FROM tblServerInfo WHERE ServerName LIKE @ServerName"
            -SqlParameters @{"ServerName = "c-is-hyperv-1"}

    .PARAMETER SQLiteConnection
        An existing SQLiteConnection to use.  We do not close this connection upon completed query.

    .PARAMETER AppendDataSource
        If specified, append the SQLite data source path to PSObject or DataRow output

    .INPUTS 
        DataSource 
            You can pipe DataSource paths to Invoke-SQLiteQuery.  The query will execute against each Data Source.

    .OUTPUTS
       As PSObject:     System.Management.Automation.PSCustomObject
       As DataRow:      System.Data.DataRow
       As DataTable:    System.Data.DataTable
       As DataSet:      System.Data.DataTableCollectionSystem.Data.DataSet
       As SingleValue:  Dependent on data type in first column.

    .EXAMPLE

        #
        # First, we create a database and a table
            $Query = "CREATE TABLE NAMES (fullname VARCHAR(20) PRIMARY KEY, surname TEXT, givenname TEXT, BirthDate DATETIME)"
            $Database = "C:\Names.SQLite"
        
            Invoke-SqliteQuery -Query $Query -DataSource $Database

        # We have a database, and a table, let's view the table info
            Invoke-SqliteQuery -DataSource $Database -Query "PRAGMA table_info(NAMES)"
                
                cid name      type         notnull dflt_value pk
                --- ----      ----         ------- ---------- --
                  0 fullname  VARCHAR(20)        0             1
                  1 surname   TEXT               0             0
                  2 givenname TEXT               0             0
                  3 BirthDate DATETIME           0             0

        # Insert some data, use parameters for the fullname and birthdate
            $query = "INSERT INTO NAMES (fullname, surname, givenname, birthdate) VALUES (@full, 'Cookie', 'Monster', @BD)"
            Invoke-SqliteQuery -DataSource $Database -Query $query -SqlParameters @{
                full = "Cookie Monster"
                BD   = (get-date).addyears(-3)
            }

        # Check to see if we inserted the data:
            Invoke-SqliteQuery -DataSource $Database -Query "SELECT * FROM NAMES"
                
                fullname       surname givenname BirthDate            
                --------       ------- --------- ---------            
                Cookie Monster Cookie  Monster   3/14/2012 12:27:13 PM

        # Insert another entry with too many characters in the fullname.
        # Illustrate that SQLite data types may be misleading:
            Invoke-SqliteQuery -DataSource $Database -Query $query -SqlParameters @{
                full = "Cookie Monster$('!' * 20)"
                BD   = (get-date).addyears(-3)
            }

            Invoke-SqliteQuery -DataSource $Database -Query "SELECT * FROM NAMES"

                fullname              surname givenname BirthDate            
                --------              ------- --------- ---------            
                Cookie Monster        Cookie  Monster   3/14/2012 12:27:13 PM
                Cookie Monster![...]! Cookie  Monster   3/14/2012 12:29:32 PM

    .EXAMPLE
        Invoke-SqliteQuery -DataSource C:\NAMES.SQLite -Query "SELECT * FROM NAMES" -AppendDataSource

            fullname       surname givenname BirthDate             Database       
            --------       ------- --------- ---------             --------       
            Cookie Monster Cookie  Monster   3/14/2012 12:55:55 PM C:\Names.SQLite

        # Append Database column (path) to each result

    .EXAMPLE
        Invoke-SqliteQuery -DataSource C:\Names.SQLite -InputFile C:\Query.sql

        # Invoke SQL from an input file

    .EXAMPLE
        $Connection = New-SQLiteConnection -DataSource :MEMORY: 
        Invoke-SqliteQuery -SQLiteConnection $Connection -Query "CREATE TABLE OrdersToNames (OrderID INT PRIMARY KEY, fullname TEXT);"
        Invoke-SqliteQuery -SQLiteConnection $Connection -Query "INSERT INTO OrdersToNames (OrderID, fullname) VALUES (1,'Cookie Monster');"
        Invoke-SqliteQuery -SQLiteConnection $Connection -Query "PRAGMA STATS"

        # Execute a query against an existing SQLiteConnection
            # Create a connection to a SQLite data source in memory
            # Create a table in the memory based datasource, verify it exists with PRAGMA STATS

    .EXAMPLE
        $Connection = New-SQLiteConnection -DataSource :MEMORY: 
        Invoke-SqliteQuery -SQLiteConnection $Connection -Query "CREATE TABLE OrdersToNames (OrderID INT PRIMARY KEY, fullname TEXT);"
        Invoke-SqliteQuery -SQLiteConnection $Connection -Query "INSERT INTO OrdersToNames (OrderID, fullname) VALUES (1,'Cookie Monster');"
        Invoke-SqliteQuery -SQLiteConnection $Connection -Query "INSERT INTO OrdersToNames (OrderID) VALUES (2);"

        # We now have two entries, only one has a fullname.  Despite this, the following command returns both; very un-PowerShell!
        Invoke-SqliteQuery -SQLiteConnection $Connection -Query "SELECT * FROM OrdersToNames" -As DataRow | Where{$_.fullname}

            OrderID fullname      
            ------- --------      
                  1 Cookie Monster
                  2               

        # Using the default -As PSObject, we can get PowerShell-esque behavior:
        Invoke-SqliteQuery -SQLiteConnection $Connection -Query "SELECT * FROM OrdersToNames" | Where{$_.fullname}

            OrderID fullname                                                                         
            ------- --------                                                                         
                  1 Cookie Monster 

    .LINK
        https://github.com/RamblingCookieMonster/Invoke-SQLiteQuery

    .LINK
        New-SQLiteConnection

    .LINK
        Invoke-SQLiteBulkCopy

    .LINK
        Out-DataTable
    
    .LINK
        https://www.sqlite.org/datatype3.html

    .LINK
        https://www.sqlite.org/lang.html

    .LINK
        http://www.sqlite.org/pragma.html

    .FUNCTIONALITY
        SQL
    #>

    [CmdletBinding( DefaultParameterSetName = 'Src-Que' )]
    [OutputType([System.Management.Automation.PSCustomObject], [System.Data.DataRow], [System.Data.DataTable], [System.Data.DataTableCollection], [System.Data.DataSet])]
    param(
        [Parameter( ParameterSetName = 'Src-Que',
            Position = 0,
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false,
            HelpMessage = 'SQLite Data Source required...' )]
        [Parameter( ParameterSetName = 'Src-Fil',
            Position = 0,
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false,
            HelpMessage = 'SQLite Data Source required...' )]
        [Alias('Path', 'File', 'FullName', 'Database')]
        [validatescript({
                #This should match memory, or the parent path should exist
                $Parent = Split-Path $_ -Parent
                if ( $_ -match ":MEMORY:|^WHAT$" -or ( $Parent -and (Test-Path $Parent)) ) {
                    $True
                }
                else {
                    Throw "Invalid datasource '$_'.`nThis must match :MEMORY:, or '$Parent' must exist"
                }
            })]
        [string[]]$DataSource,
    
        [Parameter( ParameterSetName = 'Src-Que',
            Position = 1,
            Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false )]
        [Parameter( ParameterSetName = 'Con-Que',
            Position = 1,
            Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false )]
        [string]$Query,
        
        [Parameter( ParameterSetName = 'Src-Fil',
            Position = 1,
            Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false )]
        [Parameter( ParameterSetName = 'Con-Fil',
            Position = 1,
            Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false )]
        [ValidateScript({ Test-Path $_ })]
        [string]$InputFile,

        [Parameter( Position = 2,
            Mandatory = $false,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false )]
        [Int32]$QueryTimeout = 600,
    
        [Parameter( Position = 3,
            Mandatory = $false,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false )]
        [ValidateSet("DataSet", "DataTable", "DataRow", "PSObject", "SingleValue")]
        [string]$As = "PSObject",
    
        [Parameter( Position = 4,
            Mandatory = $false,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false )]
        [System.Collections.IDictionary]$SqlParameters,

        [Parameter( Position = 5, Mandatory = $false )]
        [switch]$AppendDataSource,

        [Parameter( Position = 6, Mandatory = $false )]
        [validatescript({ Test-Path $_ })]
        [string]$AssemblyPath = $SQLiteAssembly,

        [Parameter( ParameterSetName = 'Con-Que',
            Position = 7,
            Mandatory = $true,
            ValueFromPipeline = $false,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false )]
        [Parameter( ParameterSetName = 'Con-Fil',
            Position = 7,
            Mandatory = $true,
            ValueFromPipeline = $false,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false )]
        [Alias( 'Connection', 'Conn' )]
        [System.Data.SQLite.SQLiteConnection]$SQLiteConnection
    ) 

    Begin {
        #Assembly, should already be covered by psm1
        Try {
            [void][System.Data.SQLite.SQLiteConnection]
        }
        Catch {
            if ( -not (Add-Type -path $SQLiteAssembly -PassThru -ErrorAction stop | Out-Null) ) {
                Throw "This module requires the ADO.NET driver for SQLite:`n`thttp://system.data.sqlite.org/index.html/doc/trunk/www/downloads.wiki"
            }
        }

        if ($PSBoundParameters.ContainsKey('InputFile')) { 
            $filePath = $(Resolve-Path $InputFile).path 
            $Query = [System.IO.File]::ReadAllText("$filePath")
            Write-Verbose "Extracted query from [$InputFile]"
        }
        Write-Verbose "Running Invoke-SQLiteQuery with ParameterSet '$($PSCmdlet.ParameterSetName)'.  Performing query '$Query'"

        If ($As -eq "PSObject") {
            #This code scrubs DBNulls.  Props to Dave Wyatt
            $cSharp = @'
                using System;
                using System.Data;
                using System.Management.Automation;

                public class DBNullScrubber
                {
                    public static PSObject DataRowToPSObject(DataRow row)
                    {
                        PSObject psObject = new PSObject();

                        if (row != null && (row.RowState & DataRowState.Detached) != DataRowState.Detached)
                        {
                            foreach (DataColumn column in row.Table.Columns)
                            {
                                Object value = null;
                                if (!row.IsNull(column))
                                {
                                    value = row[column];
                                }

                                psObject.Properties.Add(new PSNoteProperty(column.ColumnName, value));
                            }
                        }

                        return psObject;
                    }
                }
'@

            Try {
                if ($PSEdition -eq 'Core') {
                    # Core doesn't auto-load these assemblies unlike desktop?
                    # Not csharp coder, unsure why
                    # by fffnite
                    $Ref = @( 
                        'System.Data.Common'
                        'System.Management.Automation'
                        'System.ComponentModel.TypeConverter'
                    )
                }
                else {
                    $Ref = @(
                        'System.Data'
                        'System.Xml'
                    )
                }
                Add-Type -TypeDefinition $cSharp -ReferencedAssemblies $Ref -ErrorAction stop
            }
            Catch {
                If (-not $_.ToString() -like "*The type name 'DBNullScrubber' already exists*") {
                    Write-Warning "Could not load DBNullScrubber.  Defaulting to DataRow output: $_"
                    $As = "Datarow"
                }
            }
        }

        #Handle existing connections
        if ($PSBoundParameters.Keys -contains "SQLiteConnection") {
            if ($SQLiteConnection.State -notlike "Open") {
                Try {
                    $SQLiteConnection.Open()
                }
                Catch {
                    Throw $_
                }
            }

            if ($SQLiteConnection.state -notlike "Open") {
                Throw "SQLiteConnection is not open:`n$($SQLiteConnection | Out-String)"
            }

            $DataSource = @("WHAT")
        }
    }
    Process {
        foreach ($DB in $DataSource) {

            if ($PSBoundParameters.Keys -contains "SQLiteConnection") {
                $Conn = $SQLiteConnection
            }
            else {
                # Resolve the path entered for the database to a proper path name.
                # This accounts for a variaty of possible ways to provide a path, but
                # in the end the connection string needs a fully qualified file path.
                if ($DB -match ":MEMORY:") {
                    $Database = $DB
                }
                else {
                    $Database = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DB)    
                }
                
                if (Test-Path $Database) {
                    Write-Verbose "Querying existing Data Source '$Database'"
                }
                else {
                    Write-Verbose "Creating andn querying Data Source '$Database'"
                }

                $ConnectionString = "Data Source={0}" -f $Database

                $conn = New-Object System.Data.SQLite.SQLiteConnection -ArgumentList $ConnectionString
                $conn.ParseViaFramework = $true #Allow UNC paths, thanks to Ray Alex!
                Write-Debug "ConnectionString $ConnectionString"

                Try {
                    $conn.Open() 
                }
                Catch {
                    Write-Error $_
                    continue
                }
            }

            $cmd = $Conn.CreateCommand()
            $cmd.CommandText = $Query
            $cmd.CommandTimeout = $QueryTimeout

            if ($null -ne $SqlParameters) {
                $SqlParameters.GetEnumerator() |
                ForEach-Object {
                    If ($null -ne $_.Value) {
                        if ($_.Value -is [datetime]) { $_.Value = $_.Value.ToString("yyyy-MM-dd HH:mm:ss") }
                        $cmd.Parameters.AddWithValue("@$($_.Key)", $_.Value)
                    }
                    Else {
                        $cmd.Parameters.AddWithValue("@$($_.Key)", [DBNull]::Value)
                    }
                } > $null
            }
    
            $ds = New-Object system.Data.DataSet 
            $da = New-Object System.Data.SQLite.SQLiteDataAdapter($cmd)
    
            Try {
                [void]$da.fill($ds)
                if ($PSBoundParameters.Keys -notcontains "SQLiteConnection") {
                    $conn.Close()
                }
                $cmd.Dispose()
            }
            Catch { 
                $Err = $_
                if ($PSBoundParameters.Keys -notcontains "SQLiteConnection") {
                    $conn.Close()
                }
                switch ($ErrorActionPreference.tostring()) {
                    { 'SilentlyContinue', 'Ignore' -contains $_ } {}
                    'Stop' { Throw $Err }
                    'Continue' { Write-Error $Err }
                    Default { Write-Error $Err }
                }           
            }

            if ($AppendDataSource) {
                #Basics from Chad Miller
                $Column = New-Object Data.DataColumn
                $Column.ColumnName = "Datasource"
                $ds.Tables[0].Columns.Add($Column)

                Try {
                    #Someone better at regular expression, feel free to tackle this
                    $Conn.ConnectionString -match "Data Source=(?<DataSource>.*);"
                    $Datasrc = $Matches.DataSource.split(";")[0]
                }
                Catch {
                    $Datasrc = $DB
                }

                Foreach ($row in $ds.Tables[0]) {
                    $row.Datasource = $Datasrc
                }
            }

            switch ($As) { 
                'DataSet' {
                    $ds
                } 
                'DataTable' {
                    $ds.Tables
                } 
                'DataRow' {
                    $ds.Tables[0]
                }
                'PSObject' {
                    #Scrub DBNulls - Provides convenient results you can use comparisons with
                    #Introduces overhead (e.g. ~2000 rows w/ ~80 columns went from .15 Seconds to .65 Seconds - depending on your data could be much more!)
                    foreach ($row in $ds.Tables[0].Rows) {
                        [DBNullScrubber]::DataRowToPSObject($row)
                    }
                }
                'SingleValue' {
                    $ds.Tables[0] | Select-Object -ExpandProperty $ds.Tables[0].Columns[0].ColumnName
                }
            }
        }
    }
}

function Invoke-SQLiteBulkCopy {
    <#
    .SYNOPSIS
        Use a SQLite transaction to quickly insert data
    
    .DESCRIPTION
        Use a SQLite transaction to quickly insert data.  If we run into any errors, we roll back the transaction.
        
        The data source is not limited to SQL Server; any data source can be used, as long as the data can be loaded to a DataTable instance or read with a IDataReader instance.
    
    .PARAMETER DataSource
        Path to one ore more SQLite data sources to query 
    
    .PARAMETER Force
        If specified, skip the confirm prompt
    
    .PARAMETER  NotifyAfter
        The number of rows to fire the notification event after transferring.  0 means don't notify.  Notifications hit the verbose stream (use -verbose to see them)
    
    .PARAMETER QueryTimeout
        Specifies the number of seconds before the queries time out.
    
    .PARAMETER SQLiteConnection
        An existing SQLiteConnection to use.  We do not close this connection upon completed query.
    
    .PARAMETER ConflictClause
        The conflict clause to use in case a conflict occurs during insert. Valid values: Rollback, Abort, Fail, Ignore, Replace
    
        See https://www.sqlite.org/lang_conflict.html for more details
    
    .EXAMPLE
        #
        #Create a table
            Invoke-SqliteQuery -DataSource "C:\Names.SQLite" -Query "CREATE TABLE NAMES (
                fullname VARCHAR(20) PRIMARY KEY,
                surname TEXT,
                givenname TEXT,
                BirthDate DATETIME)" 
    
        #Build up some fake data to bulk insert, convert it to a datatable
            $DataTable = 1..10000 | %{
                [pscustomobject]@{
                    fullname = "Name $_"
                    surname = "Name"
                    givenname = "$_"
                    BirthDate = (Get-Date).Adddays(-$_)
                }
            } | Out-DataTable
    
        #Copy the data in within a single transaction (SQLite is faster this way)
            Invoke-SQLiteBulkCopy -DataTable $DataTable -DataSource $Database -Table Names -NotifyAfter 1000 -ConflictClause Ignore -Verbose 
            
    .INPUTS
        System.Data.DataTable
    
    .OUTPUTS
        None
            Produces no output
    
    .NOTES
        This function borrows from:
            Chad Miller's Write-Datatable
            jbs534's Invoke-SQLBulkCopy
            Mike Shepard's Invoke-BulkCopy from SQLPSX
    
    .LINK
        https://github.com/RamblingCookieMonster/Invoke-SQLiteQuery
    
    .LINK
        New-SQLiteConnection
    
    .LINK
        Invoke-SQLiteBulkCopy
    
    .LINK
        Out-DataTable
    
    .FUNCTIONALITY
        SQL
    #>
    [cmdletBinding( DefaultParameterSetName = 'Datasource',
        SupportsShouldProcess = $true,
        ConfirmImpact = 'High' )]
    param(
        [parameter( Position = 0,
            Mandatory = $true,
            ValueFromPipeline = $false,
            ValueFromPipelineByPropertyName = $false)]
        [System.Data.DataTable]
        $DataTable,
    
        [Parameter( ParameterSetName = 'Datasource',
            Position = 1,
            Mandatory = $true,
            ValueFromRemainingArguments = $false,
            HelpMessage = 'SQLite Data Source required...' )]
        [Alias('Path', 'File', 'FullName', 'Database')]
        [validatescript({
                #This should match memory, or the parent path should exist
                if ( $_ -match ":MEMORY:" -or (Test-Path $_) ) {
                    $True
                }
                else {
                    Throw "Invalid datasource '$_'.`nThis must match :MEMORY:, or must exist"
                }
            })]
        [string]
        $DataSource,
    
        [Parameter( ParameterSetName = 'Connection',
            Position = 1,
            Mandatory = $true,
            ValueFromPipeline = $false,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false )]
        [Alias( 'Connection', 'Conn' )]
        [System.Data.SQLite.SQLiteConnection]
        $SQLiteConnection,
    
        [parameter( Position = 2,
            Mandatory = $true)]
        [string]
        $Table,
    
        [Parameter( Position = 3,
            Mandatory = $false,
            ValueFromPipeline = $false,
            ValueFromPipelineByPropertyName = $false,
            ValueFromRemainingArguments = $false)]
        [ValidateSet("Rollback", "Abort", "Fail", "Ignore", "Replace")]
        [string]
        $ConflictClause,
    
        [int]
        $NotifyAfter = 0,
    
        [switch]
        $Force,
    
        [Int32]
        $QueryTimeout = 600
    
    )
    
    Write-Verbose "Running Invoke-SQLiteBulkCopy with ParameterSet '$($PSCmdlet.ParameterSetName)'."
    
    Function CleanUp {
        [cmdletbinding()]
        param($conn, $com, $BoundParams)
        #Only dispose of the connection if we created it
        if ($BoundParams.Keys -notcontains 'SQLiteConnection') {
            $conn.Close()
            $conn.Dispose()
            Write-Verbose "Closed connection"
        }
        $com.Dispose()
    }
    
    function Get-ParameterName {
        [CmdletBinding()]
        Param(
            [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
            [string[]]$InputObject,
    
            [Parameter(ValueFromPipelineByPropertyName = $true)]
            [string]$Regex = '(\W+)',
    
            [Parameter(ValueFromPipelineByPropertyName = $true)]
            [string]$Separator = '_'
        )
    
        Process {
            $InputObject | ForEach-Object {
                if ($_ -match $Regex) {
                    $Groups = @($_ -split $Regex | Where-Object { $_ })
                    for ($i = 0; $i -lt $Groups.Count; $i++) { if ($Groups[$i] -match $Regex) { $Groups[$i] = ($Groups[$i].ToCharArray() | ForEach-Object { [string][int]$_ }) -join $Separator } }
                    $Groups -join $Separator
                }
                else {
                    $_
                }
            }
        }
    }
    
    function New-SqliteBulkQuery {
        [CmdletBinding()]
        Param(
            [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
            [string]$Table,
    
            [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
            [string[]]$Columns,
    
            [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
            [string[]]$Parameters,
    
            [Parameter(ValueFromPipelineByPropertyName = $true)]
            [string]$ConflictClause = ''
        )
    
        Begin {
            $EscapeSingleQuote = "'", "''"
            $Delimeter = ", "
            $QueryTemplate = "INSERT{0} INTO {1} ({2}) VALUES ({3})"
        }
    
        Process {
            $fmtConflictClause = if ($ConflictClause) { " OR $ConflictClause" }
            $fmtTable = "'{0}'" -f ($Table -replace $EscapeSingleQuote)
            $fmtColumns = ($Columns | ForEach-Object { "'{0}'" -f ($_ -replace $EscapeSingleQuote) }) -join $Delimeter
            $fmtParameters = ($Parameters | ForEach-Object { "@$_" }) -join $Delimeter
            $QueryTemplate -f $fmtConflictClause, $fmtTable, $fmtColumns, $fmtParameters
        }
    }
    
    #Connections
    if ($PSBoundParameters.Keys -notcontains "SQLiteConnection") {
        if ($DataSource -match ':MEMORY:') { $Database = $DataSource } else { $Database = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DataSource) }
        $ConnectionString = "Data Source={0}" -f $Database
        $SQLiteConnection = New-Object System.Data.SQLite.SQLiteConnection -ArgumentList $ConnectionString
        $SQLiteConnection.ParseViaFramework = $true #Allow UNC paths, thanks to Ray Alex!
    }
    
    Write-Debug "ConnectionString $($SQLiteConnection.ConnectionString)"
    Try {
        if ($SQLiteConnection.State -notlike "Open") { $SQLiteConnection.Open() }
        $Command = $SQLiteConnection.CreateCommand()
        $Command.Timeout = $QueryTimeout
        $Transaction = $SQLiteConnection.BeginTransaction()
    }
    Catch { Throw $_ }
        
    write-verbose "DATATABLE IS $($DataTable.gettype().fullname) with value $($Datatable | out-string)"
    $RowCount = $Datatable.Rows.Count
    Write-Verbose "Processing datatable with $RowCount rows"
    
    if ($Force -or $PSCmdlet.ShouldProcess("$($DataTable.Rows.Count) rows, with BoundParameters $($PSBoundParameters | Out-String)", "SQL Bulk Copy")) {
        #Get column info...
        [array]$Columns = $DataTable.Columns | Select-Object -ExpandProperty ColumnName
        $ColumnTypeHash = @{}
        $ColumnToParamHash = @{}
        $Index = 0
        foreach ($Col in $DataTable.Columns) {
            $Type = Switch -regex ($Col.DataType.FullName) {
                # I figure we create a hashtable, can act upon expected data when doing insert
                # Might be a better way to handle this...
                '^(|\ASystem\.)Boolean$' { "BOOLEAN" } #I know they're fake...
                '^(|\ASystem\.)Byte\[\]' { "BLOB" }
                '^(|\ASystem\.)Byte$' { "BLOB" }
                '^(|\ASystem\.)Datetime$' { "DATETIME" }
                '^(|\ASystem\.)Decimal$' { "REAL" }
                '^(|\ASystem\.)Double$' { "REAL" }
                '^(|\ASystem\.)Guid$' { "TEXT" }
                '^(|\ASystem\.)Int16$' { "INTEGER" }
                '^(|\ASystem\.)Int32$' { "INTEGER" }
                '^(|\ASystem\.)Int64$' { "INTEGER" }
                '^(|\ASystem\.)UInt16$' { "INTEGER" }
                '^(|\ASystem\.)UInt32$' { "INTEGER" }
                '^(|\ASystem\.)UInt64$' { "INTEGER" }
                '^(|\ASystem\.)Single$' { "REAL" }
                '^(|\ASystem\.)String$' { "TEXT" }
                Default { "BLOB" } #Let SQLite handle the rest...
            }
    
            #We ref columns by their index, so add that...
            $ColumnTypeHash.Add($Index, $Type)
    
            # Parameter names can only be alphanumeric: https://www.sqlite.org/c3ref/bind_blob.html
            # So we have to replace all non-alphanumeric chars in column name to use it as parameter later.
            # This builds hashtable to correlate column name with parameter name.
            $ColumnToParamHash.Add($Col.ColumnName, (Get-ParameterName $Col.ColumnName))
    
            $Index++
        }
    
        #Build up the query
        if ($PSBoundParameters.ContainsKey('ConflictClause')) {
            $Command.CommandText = New-SqliteBulkQuery -Table $Table -Columns $ColumnToParamHash.Keys -Parameters $ColumnToParamHash.Values -ConflictClause $ConflictClause
        }
        else {
            $Command.CommandText = New-SqliteBulkQuery -Table $Table -Columns $ColumnToParamHash.Keys -Parameters $ColumnToParamHash.Values
        }
    
        foreach ($Column in $Columns) {
            $param = New-Object System.Data.SQLite.SqLiteParameter $ColumnToParamHash[$Column]
            [void]$Command.Parameters.Add($param)
        }
                
        for ($RowNumber = 0; $RowNumber -lt $RowCount; $RowNumber++) {
            $row = $Datatable.Rows[$RowNumber]
            for ($col = 0; $col -lt $Columns.count; $col++) {
                # Depending on the type of thid column, quote it
                # For dates, convert it to a string SQLite will recognize
                switch ($ColumnTypeHash[$col]) {
                    "BOOLEAN" { $Command.Parameters[$ColumnToParamHash[$Columns[$col]]].Value = [int][boolean]$row[$col] }
                    "DATETIME" {
                        Try { $Command.Parameters[$ColumnToParamHash[$Columns[$col]]].Value = $row[$col].ToString("yyyy-MM-dd HH:mm:ss") }
                        Catch { $Command.Parameters[$ColumnToParamHash[$Columns[$col]]].Value = $row[$col] }
                    }
                    Default { $Command.Parameters[$ColumnToParamHash[$Columns[$col]]].Value = $row[$col] }
                }
            }
    
            #We have the query, execute!
            Try { [void]$Command.ExecuteNonQuery() }
            Catch {
                #Minimal testing for this rollback...
                Write-Verbose "Rolling back due to error:`n$_"
                $Transaction.Rollback()
                            
                #Clean up and throw an error
                CleanUp -conn $SQLiteConnection -com $Command -BoundParams $PSBoundParameters
                Throw "Rolled back due to error:`n$_"
            }    
            if ($NotifyAfter -gt 0 -and $($RowNumber % $NotifyAfter) -eq 0) { Write-Verbose "Processed $($RowNumber + 1) records" }
        }  
    }        
    #Commit the transaction and clean up the connection
    $Transaction.Commit()
    CleanUp -conn $SQLiteConnection -com $Command -BoundParams $PSBoundParameters        
}

function Out-DataTable {
    <#
    .SYNOPSIS
        Creates a DataTable for an object

    .DESCRIPTION
        Creates a DataTable based on an object's properties.

    .PARAMETER InputObject
        One or more objects to convert into a DataTable

    .PARAMETER NonNullable
        A list of columns to set disable AllowDBNull on

    .INPUTS
        Object
            Any object can be piped to Out-DataTable

    .OUTPUTS
    System.Data.DataTable

    .EXAMPLE
        $dt = Get-psdrive | Out-DataTable
        
        # This example creates a DataTable from the properties of Get-psdrive and assigns output to $dt variable

    .EXAMPLE
        Get-Process | Select Name, CPU | Out-DataTable | Invoke-SQLBulkCopy -ServerInstance $SQLInstance -Database $Database -Table $SQLTable -force -verbose

        # Get a list of processes and their CPU, create a datatable, bulk import that data

    .NOTES
        Adapted from script by Marc van Orsouw and function from Chad Miller
        Version History
        v1.0  - Chad Miller - Initial Release
        v1.1  - Chad Miller - Fixed Issue with Properties
        v1.2  - Chad Miller - Added setting column datatype by property as suggested by emp0
        v1.3  - Chad Miller - Corrected issue with setting datatype on empty properties
        v1.4  - Chad Miller - Corrected issue with DBNull
        v1.5  - Chad Miller - Updated example
        v1.6  - Chad Miller - Added column datatype logic with default to string
        v1.7  - Chad Miller - Fixed issue with IsArray
        v1.8  - ramblingcookiemonster - Removed if($Value) logic.  This would not catch empty strings, zero, $false and other non-null items
                                    - Added perhaps pointless error handling

    .LINK
        https://github.com/RamblingCookieMonster/PowerShell

    .LINK
        Invoke-SQLBulkCopy

    .LINK
        Invoke-Sqlcmd2

    .LINK
        New-SQLConnection

    .FUNCTIONALITY
        SQL
    #>
    [CmdletBinding()]
    [OutputType([System.Data.DataTable])]
    param(
        [Parameter( Position = 0,
            Mandatory = $true,
            ValueFromPipeline = $true)]
        [PSObject[]]$InputObject,

        [string[]]$NonNullable = @()
    )

    Begin {
        $dt = New-Object Data.datatable  
        $First = $true 

        function Get-ODTType {
            param($type)

            $types = @(
                'System.Boolean',
                'System.Byte[]',
                'System.Byte',
                'System.Char',
                'System.Datetime',
                'System.Decimal',
                'System.Double',
                'System.Guid',
                'System.Int16',
                'System.Int32',
                'System.Int64',
                'System.Single',
                'System.UInt16',
                'System.UInt32',
                'System.UInt64')

            if ( $types -contains $type ) { Write-Output "$type" } else { Write-Output 'System.String' }
        } #Get-Type
    }
    Process {
        foreach ($Object in $InputObject) {
            $DR = $DT.NewRow()  
            foreach ($Property in $Object.PsObject.Properties) {
                $Name = $Property.Name
                $Value = $Property.Value
                
                #RCM: what if the first property is not reflective of all the properties?  Unlikely, but...
                if ($First) {
                    $Col = New-Object Data.DataColumn  
                    $Col.ColumnName = $Name  
                    
                    #If it's not DBNull or Null, get the type
                    if ($Value -isnot [System.DBNull] -and $null -ne $Value) { $Col.DataType = [System.Type]::GetType( $(Get-ODTType $property.TypeNameOfValue) ) }
                    
                    #Set it to nonnullable if specified
                    if ($NonNullable -contains $Name ) { $col.AllowDBNull = $false }
                    try { $DT.Columns.Add($Col) }
                    catch { Write-Error "Could not add column $($Col | Out-String) for property '$Name' with value '$Value' and type '$($Value.GetType().FullName)':`n$_" }
                }  
                
                Try {
                    #Handle arrays and nulls
                    if ($property.GetType().IsArray) {
                        $DR.Item($Name) = $Value | ConvertTo-XML -As String -NoTypeInformation -Depth 1
                    } elseif ($null -ne $Value) {
                        $DR.Item($Name) = [DBNull]::Value
                    } else {
                        $DR.Item($Name) = $Value
                    }
                }
                Catch {
                    Write-Error "Could not add property '$Name' with value '$Value' and type '$($Value.GetType().FullName)'"
                    continue
                }

                #Did we get a null or dbnull for a non-nullable item?  let the user know.
                if ($NonNullable -contains $Name -and ($Value -is [System.DBNull] -or $null -ne $Value)) { write-verbose "NonNullable property '$Name' with null value found: $($object | out-string)" }
            } 
            Try { $DT.Rows.Add($DR) }
            Catch { Write-Error "Failed to add row '$($DR | Out-String)':`n$_" }
            $First = $false
        }
    } 
    End { Write-Output @(, $dt) }
} #Out-DataTable
