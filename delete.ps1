#####################################################
# HelloID-Conn-Prov-Target-SQL-Delete
#
# Version: 1.0.0
#####################################################

$c = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$aRef = $accountReference | ConvertFrom-Json
$m = $manager | ConvertFrom-Json
$mRef = $managerAccountReference | ConvertFrom-Json
$success = $false
$auditLogs = [Collections.Generic.List[PSCustomObject]]::new()

# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($($c.isDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}
$InformationPreference = "Continue"
$WarningPreference = "Continue"

# Used to connect to SQL server.
$connectionString = $c.connectionString
$username = $c.username # Only use when you want to connect using SQL credentials
$password = $c.password # Only use when you want to connect using SQL credentials
$table = $c.table

#Change mapping here

# Troubleshooting
# $dryRun = $false
# $aRef = @{ EmployeeId = "Test1" }

$correlationProperty = "EmployeeId"
$correlationValue = $aRef.EmployeeId # Has to match the AFAS value of the specified filter field ($filterfieldid)

#region functions
function Invoke-SQLQuery {
    param(
        [parameter(Mandatory = $true)]
        $ConnectionString,

        [parameter(Mandatory = $false)]
        $Username,

        [parameter(Mandatory = $false)]
        $Password,

        [parameter(Mandatory = $true)]
        $SqlQuery,

        [parameter(Mandatory = $true)]
        [ref]$Data
    )
    try {
        $Data.value = $null

        # Initialize connection and execute query
        if (-not[String]::IsNullOrEmpty($Username) -and -not[String]::IsNullOrEmpty($Password)) {
            # First create the PSCredential object
            $securePassword = ConvertTo-SecureString -String $Password -AsPlainText -Force
            $credential = [System.Management.Automation.PSCredential]::new($Username, $securePassword)
 
            # Set the password as read only
            $credential.Password.MakeReadOnly()
 
            # Create the SqlCredential object
            $sqlCredential = [System.Data.SqlClient.SqlCredential]::new($credential.username, $credential.password)
        }
        # Connect to the SQL server
        $SqlConnection = [System.Data.SqlClient.SqlConnection]::new()
        $SqlConnection.ConnectionString = “$ConnectionString”
        if (-not[String]::IsNullOrEmpty($sqlCredential)) {
            $SqlConnection.Credential = $sqlCredential
        }
        $SqlConnection.Open()
        Write-Verbose "Successfully connected to SQL database" 

        # Set the query
        $SqlCmd = [System.Data.SqlClient.SqlCommand]::new()
        $SqlCmd.Connection = $SqlConnection
        $SqlCmd.CommandText = $SqlQuery

        # Set the data adapter
        $SqlAdapter = [System.Data.SqlClient.SqlDataAdapter]::new()
        $SqlAdapter.SelectCommand = $SqlCmd

        # Set the output with returned data
        $DataSet = [System.Data.DataSet]::new()
        $null = $SqlAdapter.Fill($DataSet)

        # Set the output with returned data
        $Data.value = $DataSet.Tables[0] | Select-Object -Property * -ExcludeProperty RowError, RowState, Table, ItemArray, HasErrors
    }
    catch {
        $Data.Value = $null
        Write-Error $_
    }
    finally {
        if ($SqlConnection.State -eq "Open") {
            $SqlConnection.close()
        }
        Write-Verbose "Successfully disconnected from SQL database"
    }
}
#endregion functions

# Get current SQL record
try {
    Write-Verbose "Querying record from SQL table '$($table)' where '$($correlationProperty)'='$($correlationValue)'"
    $sqlQueryGetCurrentAccount = "
    SELECT
        * 
    FROM
        $table
    WHERE
        $correlationProperty = '$correlationValue'"

    $sqlQueryGetCurrentAccountResult = [System.Collections.ArrayList]::new()
    $sqlQueryGetCurrentAccountSplatParams = @{
        ConnectionString = $connectionString
        SqlQuery         = $sqlQueryGetCurrentAccount
        ErrorAction      = 'Stop'
    }

    Invoke-SQLQuery @sqlQueryGetCurrentAccountSplatParams -Data ([ref]$sqlQueryGetCurrentAccountResult)
    $currentAccount = $sqlQueryGetCurrentAccountResult
    Write-Verbose "Successfully queried record from SQL table '$($table)' where '$($correlationProperty)'='$($correlationValue)'. Result count: $($currentAccount.$correlationProperty.Count)"

    if ([String]::IsNullOrEmpty($currentAccount.$correlationProperty)) {
        throw "No record found in SQL table '$($table)' where '$($correlationProperty)'='$($correlationValue)'"
    }
}
catch {
    $ex = $PSItem
    $verboseErrorMessage = $ex.Exception.Message
    $auditErrorMessage = $ex.Exception.Message

    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)"

    if ($auditErrorMessage -Like "No record found in SQL table '$($table)' where '$($correlationProperty)'='$($correlationValue)'") {
        $success = $true
        $auditLogs.Add([PSCustomObject]@{
                Action  = "DeleteAccount"
                Message = "No record found in SQL table '$($table)' where '$($correlationProperty)'='$($correlationValue)'. Possibly already deleted."
                IsError = $false
            })
    }
    else {
        $success = $false  
        $auditLogs.Add([PSCustomObject]@{
                Action  = "DeleteAccount"
                Message = "Error querying record from SQL table '$($table)' where '$($correlationProperty)'='$($correlationValue)'. Sql Query: [$sqlQueryGetCurrentAccount]. Error Message: $auditErrorMessage"
                IsError = $True
            })
    }
}

# Delete SQL record
try {
    if (-not[String]::IsNullOrEmpty($currentAccount.$correlationProperty)) {
        try {
            Write-Verbose "Deleting record in SQL table '$($table)' where '$($correlationProperty)'='$($correlationValue)'"

            $sqlQueryDeleteCurrentAccount = "
                    DELETE
                    FROM
                        $table
                    WHERE
                        $correlationProperty = '$correlationValue'"
            
            $sqlQueryDeleteCurrentAccountResult = [System.Collections.ArrayList]::new()
            $sqlQueryDeleteCurrentAccountSplatParams = @{
                ConnectionString = $connectionString
                SqlQuery         = $sqlQueryDeleteCurrentAccount
                ErrorAction      = 'Stop'
            }
            
            if (-not($dryRun -eq $true)) {
                Invoke-SQLQuery @sqlQueryDeleteCurrentAccountSplatParams -Data ([ref]$sqlQueryDeleteCurrentAccountResult)
                $deletedAccount = $sqlQueryDeleteCurrentAccountResult

                $auditLogs.Add([PSCustomObject]@{
                        Action  = "DeleteAccount"
                        Message = "Successfully deleted record in SQL table '$($table)' where '$($correlationProperty)'='$($correlationValue)'"
                        IsError = $false
                    })
            }
            else {
                Write-Warning "DryRun: Would delete record in SQL table '$($table)' where '$($correlationProperty)'='$($correlationValue)'"
            }
            break
        }
        catch {
            $ex = $PSItem
            $verboseErrorMessage = $ex.Exception.Message
            $auditErrorMessage = $ex.Exception.Message
            
            Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)"
            
            $success = $false  
            $auditLogs.Add([PSCustomObject]@{
                    Action  = "DeleteAccount"
                    Message = "Error deleting record in SQL table '$($table)' where '$($correlationProperty)'='$($correlationValue)'. Sql Query: [$sqlQueryDeleteCurrentAccount]. Error Message: $auditErrorMessage"
                    IsError = $True
                })
        }
    }
}
finally {
    # Send results
    $result = [PSCustomObject]@{
        Success   = $success
        Auditlogs = $auditLogs
        Account   = $account
    }

    Write-Output $result | ConvertTo-Json -Depth 10
}