#################################################
# HelloID-Conn-Prov-Target-SQL-Disable
# PowerShell V2
#################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

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
        Write-Information "Successfully connected to SQL database" 

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
        Write-Information "Successfully disconnected from SQL database"
    }
}
#endregion

try {
    # Verify if [aRef] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }

    $correlationField = $actionContext.CorrelationConfiguration.accountField
    $correlationValue = $actionContext.References.Account

    Write-Information "Verifying if a SQL account for [$($personContext.Person.DisplayName)] exists"    
    $sqlQueryGetCurrentAccount = "
        SELECT 
            * 
        FROM 
            $($actionContext.Configuration.table) 
        WHERE 
            $correlationField = '$correlationValue'"

    $sqlQueryGetCurrentAccountResult = [System.Collections.ArrayList]::new()
    $sqlQueryGetCurrentAccountSplatParams = @{
        ConnectionString = $actionContext.Configuration.connectionString
        SqlQuery         = $sqlQueryGetCurrentAccount
        ErrorAction      = 'Stop'
    }

    Invoke-SQLQuery @sqlQueryGetCurrentAccountSplatParams -Data ([ref]$sqlQueryGetCurrentAccountResult)
    $correlatedAccount = $sqlQueryGetCurrentAccountResult
        
    $outputContext.PreviousData.Active = [string][int]$correlatedAccount.Active

    if ($null -ne $correlatedAccount) {
        $action = 'DisableAccount'
        $dryRunMessage = "Disable SQL account: [$($actionContext.References.Account)] for person: [$($personContext.Person.DisplayName)] will be executed during enforcement"
    }
    else {
        $action = 'NotFound'
        $dryRunMessage = "SQL account: [$($actionContext.References.Account)] for person: [$($personContext.Person.DisplayName)] could not be found, possibly indicating that it could be deleted, or the account is not correlated"
    }

    # Add a message and the result of each of the validations showing what will happen during enforcement
    if ($actionContext.DryRun -eq $true) {
        Write-Information "[DryRun] $dryRunMessage"
    }

    # Process
    if (-not($actionContext.DryRun -eq $true)) {
        switch ($action) {
            'DisableAccount' {                
                Write-Information "Disabling SQL account with accountReference: [$($actionContext.References.Account)]"

                $sqlQueryDisableAccount = "
                UPDATE
                    $($actionContext.Configuration.table)
                SET
                    Active = $($actionContext.Data.Active)
                WHERE
                    $correlationField = '$correlationValue'"                    

                $sqlQueryDisableAccountResult = [System.Collections.ArrayList]::new()
                $sqlQuerDisableAccountSplatParams = @{
                    ConnectionString = $actionContext.Configuration.connectionString
                    SqlQuery         = $sqlQueryDisableAccount
                    ErrorAction      = 'Stop'
                }

                Invoke-SQLQuery @sqlQuerDisableAccountSplatParams -Data ([ref]$sqlQueryDisableAccountResult)
                $null = $sqlQueryDisableAccountResult

                $outputContext.Data = $actionContext.Data
                $outputContext.AccountReference = $correlationValue

                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Action  = $action
                        Message = "Successfully disabled account in SQL table '$($actionContext.Configuration.table)' where '$($correlationField)'='$($correlationValue)'."
                        IsError = $false
                    })
                
                break
            }
            'NotFound' {                
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Action  = 'DisableAccount'
                        Message = "SQL account: [$($actionContext.References.Account)] for person: [$($personContext.Person.DisplayName)] could not be found, possibly indicating that it could be deleted, or the account is not correlated"
                        IsError = $false
                    })                
                break
            }
        }
        $outputContext.Success = $true
    }
}
catch {        
    $ex = $PSItem
   
    $auditMessage = "Could not disable SQL account. Error: $($ex.Exception.Message)"
    Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
   
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Action  = "DisableAccount"
            Message = $auditMessage
            IsError = $true
        })
}