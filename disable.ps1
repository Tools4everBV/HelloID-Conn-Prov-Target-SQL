#################################################
# HelloID-Conn-Prov-Target-SQL-Disable
# PowerShell V2
#################################################
$outputContext.success = $true

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($actionContext.Configuration.isDebug) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

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

function Resolve-SQLError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }
        if (-not [string]::IsNullOrEmpty($ErrorObject.ErrorDetails.Message)) {
            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            if ($null -ne $ErrorObject.Exception.Response) {
                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                if (-not [string]::IsNullOrEmpty($streamReaderResponse)) {
                    $httpErrorObj.ErrorDetails = $streamReaderResponse
                }
            }
        }
        try {
            # $errorDetailsObject = ($httpErrorObj.ErrorDetails | ConvertFrom-Json)
            # Make sure to inspect the error result object and add only the error message as a FriendlyMessage.
            # $httpErrorObj.FriendlyMessage = $errorDetailsObject.message
            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails # Temporarily assignment
        }
        catch {
            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
        }
        Write-Output $httpErrorObj
    }
}
#endregion

try {
    # Verify if [aRef] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }

    $correlationField = $actionContext.CorrelationConfiguration.accountField
    $correlationValue = $actionContext.CorrelationConfiguration.accountFieldValue

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
                try {
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
                }
                catch {
                    
                    $ex = $PSItem
                    $verboseErrorMessage = $ex.Exception.Message
                    $auditErrorMessage = $ex.Exception.Message
        
                    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)"
        
                    $auditLogs.Add([PSCustomObject]@{
                            Action  = $action
                            Message = "Error disabling account in SQL table '$($actionContext.Configuration.table)' where '$($correlationProperty)'='$($correlationValue)'. Sql Query: [$sqlQueryCreateNewAccount]. Error Message: $auditErrorMessage"
                            IsError = $True
                        })
                    
                }
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
    }
}
catch {        
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-SQLError Error -ErrorObject $ex
        $auditMessage = "Could not disable SQL account. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Could not disable SQL account. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Action  = "DisableAccount"
            Message = $auditMessage
            IsError = $true
        })
}
finally {
    # Check if auditLogs contains errors, if errors are found, set success to false
    if ($outputContext.AuditLogs.IsError -contains $true) {
        $outputContext.Success = $false
    }
}