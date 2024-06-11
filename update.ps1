#################################################
# HelloID-Conn-Prov-Target-SQL-Update
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
    $outputContext.PreviousData = $correlatedAccount


    # Always compare the account against the current account in target system
    if ($null -ne $correlatedAccount) {
        $splatCompareProperties = @{            
            ReferenceObject  = @( ($correlatedAccount | Select-Object *).PSObject.Properties )
            DifferenceObject = @( ($actionContext.Data | Select-Object *).PSObject.Properties )
        }

        $propertiesChanged = Compare-Object @splatCompareProperties -PassThru | Where-Object { $_.SideIndicator -eq '=>' }
        
        if ($propertiesChanged) {
            $action = 'UpdateAccount'
            $dryRunMessage = "Account property(s) required to update: $($propertiesChanged.Name -join ', ')"
        }
        else {
            $action = 'NoChanges'
            $dryRunMessage = 'No changes will be made to the account during enforcement'
        }
    }
    else {
        $action = 'NotFound'
        $dryRunMessage = "SQL account for: [$($personContext.Person.DisplayName)] not found. Possibly deleted."
    }


    # Add a message and the result of each of the validations showing what will happen during enforcement
    if ($actionContext.DryRun -eq $true) {
        Write-Information "[DryRun] $dryRunMessage"
    }

    # Process
    if (-not($actionContext.DryRun -eq $true)) {
        switch ($action) {            
            'UpdateAccount' {
                
                Write-Information "Updating SQL account with accountReference: [$($actionContext.References.Account)]"

                # Make sure to test with special characters and if needed; add utf8 encoding.

                # Create list of porperties to update
                [System.Collections.ArrayList]$sqlQueryUpdateProperties = @()
                foreach ($property in $propertiesChanged) {
                    # Enclose Name with brackets [] and Value with single quotes ''
                    $null = $sqlQueryUpdateProperties.Add("[$($property.Name)] = '$($property.Value)'")
                }

                $sqlQueryUpdateCurrentAccount = "
                            UPDATE
                                $($actionContext.Configuration.table)
                            SET
                                $($sqlQueryUpdateProperties -join ',')
                            WHERE
                                $correlationField = '$correlationValue'"
                    

                $sqlQueryUpdateCurrentAccountResult = [System.Collections.ArrayList]::new()
                $sqlQueryUpdateCurrentAccountSplatParams = @{
                    ConnectionString = $actionContext.Configuration.connectionString
                    SqlQuery         = $sqlQueryUpdateCurrentAccount
                    ErrorAction      = 'Stop'
                }

                Invoke-SQLQuery @sqlQueryUpdateCurrentAccountSplatParams -Data ([ref]$sqlQueryUpdateCurrentAccountResult)
                $updatedAccount = $sqlQueryUpdateCurrentAccountResult

                $outputContext.Success = $true
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Action  = $action
                        Message = "Update account was successful, Account property(s) updated: [$($propertiesChanged.name -join ',')]"                            
                        IsError = $false
                    })
                
                break
            }            

            'NoChanges' {
                Write-Information "No changes to SQL account with accountReference: [$($actionContext.References.Account)]"
                $outputContext.Success = $true
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Action  = 'UpdateAccount'
                        Message = 'No changes will be made to the account during enforcement'
                        IsError = $false
                    })
                break
            }

            'NotFound' {
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Action  = 'UpdateAccount'
                        Message = "SQL account with accountReference: [$($actionContext.References.Account)] could not be found, possibly indicating that it could be deleted, or the account is not correlated"
                        IsError = $true
                    })
                break
            }
        }
    }
}
catch {    
    $ex = $PSItem
    
    $auditMessage = "Could not update SQL account. Error: $($ex.Exception.Message)"
    Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Action  = 'UpdateAccount'
            Message = $auditMessage
            IsError = $true
        })
}

