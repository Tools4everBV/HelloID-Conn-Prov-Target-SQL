#################################################
# HelloID-Conn-Prov-Target-SQL-Create
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
    # Initial Assignments
    $outputContext.AccountReference = 'Currently not available'

    # Validate correlation configuration
    if ($actionContext.CorrelationConfiguration.Enabled) {
        $correlationField = $actionContext.CorrelationConfiguration.accountField
        $correlationValue = $actionContext.CorrelationConfiguration.accountFieldValue

        if ([string]::IsNullOrEmpty($($correlationField))) {
            throw 'Correlation is enabled but not configured correctly'
        }
        if ([string]::IsNullOrEmpty($($correlationValue))) {
            throw 'Correlation is enabled but [accountFieldValue] is empty. Please make sure it is correctly mapped'
        }

        # Verify if a user must be either [created ] or just [correlated]
        Write-Information "Querying record from SQL table '$($actionContext.Configuration.table)' where '$($correlationField)'='$($correlationValue)'"
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
    }
    else {
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Action  = "CorrelateAccount"
                Message = "Configuration of correlation is madatory."
                IsError = $true
            })
        Throw "Configuration of correlation is mandatory."
    }

    if ($null -ne $correlatedAccount) {        
        $action = 'CorrelateAccount'
    }
    else {
        $action = 'CreateAccount'
    }

    # Add a message and the result of each of the validations showing what will happen during enforcement
    if ($actionContext.DryRun -eq $true) {
        Write-Information "[DryRun] $action SQL account for: [$($personContext.Person.DisplayName)], will be executed during enforcement"
    }
    
    # Process
    if (-not($actionContext.DryRun -eq $true)) {
        switch ($action) {
            'CreateAccount' {
                
                Write-Information "Creating record in SQL table '$($actionContext.Configuration.table)' where '$($correlationField)'='$($correlationValue)'"

                # Create list of property names and values
                [System.Collections.ArrayList]$sqlQueryCreateProperties = @()
                [System.Collections.ArrayList]$sqlQueryCreateValues = @()
                foreach ($property in $actionContext.Data.PSObject.Properties) {
                    # Enclose Name with brackets []
                    $null = $sqlQueryCreateProperties.Add("[$($property.Name)]")
                    # Enclose Value with single quotes ''
                    $null = $sqlQueryCreateValues.Add("'$($property.Value)'")
                }

                $sqlQueryCreateNewAccount = "
                    INSERT INTO $($actionContext.Configuration.table) 
                        ($($sqlQueryCreateProperties -join ',')) 
                    VALUES 
                        ($($sqlQueryCreateValues -join ','))"
            
                $sqlQueryCreateNewAccountResult = [System.Collections.ArrayList]::new()
                $sqlQueryCreateNewAccountSplatParams = @{
                    ConnectionString = $actionContext.Configuration.connectionString
                    SqlQuery         = $sqlQueryCreateNewAccount
                    ErrorAction      = 'Stop'
                }

                Invoke-SQLQuery @sqlQueryCreateNewAccountSplatParams -Data ([ref]$sqlQueryCreateNewAccountResult)
                $createdAccount = $sqlQueryCreateNewAccountResult

                $outputContext.Data = $actionContext.Data
                $outputContext.AccountReference = $correlationValue

                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Action  = $action
                        Message = "Successfully created record in SQL table '$($actionContext.Configuration.table)' where '$($correlationProperty)'='$($correlationValue)'."
                        IsError = $false
                    })
                
                break                    
            }

            'CorrelateAccount' {
                Write-Information 'Correlating SQL account'

                $outputContext.Data = $actionContext.Data
                $outputContext.AccountReference = $correlationValue
                $outputContext.AccountCorrelated = $true
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Action  = $action
                        Message = "Correlated account: [$($correlatedAccount.DisplayName)] on field: [$($correlationField)] with value: [$($correlationValue)]"
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
    
    $auditMessage = "Could not create or correlate SQL account. Error: $($ex.Exception.Message)"
    Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Action  = "CreateAccount"
            Message = $auditMessage            
            IsError = $true
        })
}