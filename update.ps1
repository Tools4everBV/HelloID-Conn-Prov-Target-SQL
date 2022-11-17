#####################################################
# HelloID-Conn-Prov-Target-SQL-Update
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
# Enclose all values in double quotes, since the SQL values are always a string
$account = [PSCustomObject]@{
    'EmployeeId'       = "$($p.ExternalId)"
    'Nickname'         = "$($p.Name.NickName)"
    'Birthname'        = "$($p.Name.FamilyName)"
    'Business Email'   = "$($p.Contact.Business.Email)"
    'Birthname prefix' = "$($p.Name.FamilyNamePrefix)"
    'Department'       = "$($p.PrimaryContract.Department.DisplayName)"
    'Jobtitle'         = "$($p.PrimaryContract.Title.Name)"
    'Employer'         = "$($p.PrimaryContract.Employer.Name)"
}


# Troubleshooting
# $dryRun = $false
# $aRef = @{ EmployeeId = "Test1" }
# $account = [PSCustomObject]@{
#     'EmployeeId'       = 'Test1'
#     'Nickname'         = 'Test'
#     'Birthname'        = "HelloID1"
#     'Business Email'   = "TestHelloID1@test.nl"
#     'Birthname prefix' = "van der"
#     'Department'       = "Testing"
#     'Jobtitle'         = "Testaccount"
#     'Employer'         = "HelloID"
# }

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

    if (-not[String]::IsNullOrEmpty($currentAccount.$correlationProperty)) {
        Write-Verbose "Existing record found in SQL table '$($table)' where '$($correlationProperty)'='$($correlationValue)'"
        
        #Verify if the account must be updated
        $splatCompareProperties = @{
            ReferenceObject  = @( ($currentAccount | Select-Object *).PSObject.Properties )
            DifferenceObject = @( ($account | Select-Object *).PSObject.Properties )
        }
        $propertiesChanged = (Compare-Object @splatCompareProperties -PassThru).Where( { $_.SideIndicator -eq '=>' })

        if ($propertiesChanged) {
            Write-Verbose "Account property(s) required to update: [$($propertiesChanged -join ",")]"
            $updateAction = 'Update'
        }
        else {
            $updateAction = 'NoChanges'
        }
    } 
    else {
        throw "No record found in SQL table '$($table)' where '$($correlationProperty)'='$($correlationValue)'"
    }
}
catch {
    $ex = $PSItem
    $verboseErrorMessage = $ex.Exception.Message
    $auditErrorMessage = $ex.Exception.Message

    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)"

    if ($auditErrorMessage -Like "No record found in SQL table '$($table)' where '$($correlationProperty)'='$($correlationValue)'") {
        $success = $false
        $auditLogs.Add([PSCustomObject]@{
                Action  = "UpdateAccount"
                Message = "No record found in SQL table '$($table)' where '$($correlationProperty)'='$($correlationValue)'. Possibly deleted."
                IsError = $true
            })
    }
    else {
        $success = $false  
        $auditLogs.Add([PSCustomObject]@{
                Action  = "UpdateAccount"
                Message = "Error querying record from SQL table '$($table)' where '$($correlationProperty)'='$($correlationValue)'. Sql Query: [$sqlQueryGetCurrentAccount]. Error Message: $auditErrorMessage"
                IsError = $True
            })
    }
}

# Update SQL record
try {
    if (-not[String]::IsNullOrEmpty($currentAccount.$correlationProperty)) {
        switch ($updateAction) {
            'Update' {
                try {
                    Write-Verbose "Updating record in SQL table '$($table)' where '$($correlationProperty)'='$($correlationValue)'"

                    # Create list of porperties to update
                    [System.Collections.ArrayList]$sqlQueryUpdateProperties = @()
                    foreach ($property in $propertiesChanged) {
                        # Enclose Name with brackets [] and Value with single quotes ''
                        $null = $sqlQueryUpdateProperties.Add("[$($property.Name)] = '$($property.Value)'")
                    }

                    $sqlQueryUpdateCurrentAccount = "
                            UPDATE
                                $table
                            SET
                                $($sqlQueryUpdateProperties -join ',')
                            WHERE
                                $correlationProperty = '$correlationValue'"
                    
                    $sqlQueryUpdateCurrentAccountResult = [System.Collections.ArrayList]::new()
                    $sqlQueryUpdateCurrentAccountSplatParams = @{
                        ConnectionString = $connectionString
                        SqlQuery         = $sqlQueryUpdateCurrentAccount
                        ErrorAction      = 'Stop'
                    }
                    
                    if (-not($dryRun -eq $true)) {
                        Invoke-SQLQuery @sqlQueryUpdateCurrentAccountSplatParams -Data ([ref]$sqlQueryUpdateCurrentAccountResult)
                        $updatedAccount = $sqlQueryUpdateCurrentAccountResult

                        $auditLogs.Add([PSCustomObject]@{
                                Action  = "UpdateAccount"
                                Message = "Successfully updated record in SQL table '$($table)' where '$($correlationProperty)'='$($correlationValue)'. Properties updated: [$($sqlQueryUpdateProperties -join ',')]"
                                IsError = $false
                            })
                    }
                    else {
                        Write-Warning "DryRun: Would update record in SQL table '$($table)' where '$($correlationProperty)'='$($correlationValue)'. Properties to update: [$($sqlQueryUpdateProperties -join ',')]"
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
                            Action  = "UpdateAccount"
                            Message = "Error updating record in SQL table '$($table)' where '$($correlationProperty)'='$($correlationValue)'. Sql Query: [$sqlQueryUpdateCurrentAccount]. Error Message: $auditErrorMessage"
                            IsError = $True
                        })
                }
            }
            'NoChanges' {
                Write-Verbose "No changes to record in SQL table '$($table)' where '$($correlationProperty)'='$($correlationValue)'"

                if (-not($dryRun -eq $true)) {
                    $auditLogs.Add([PSCustomObject]@{
                            Action  = "UpdateAccount"
                            Message = "Successfully updated record in SQL table '$($table)' where '$($correlationProperty)'='$($correlationValue)' (No Changes needed)"
                            IsError = $false
                        })
                }
                else {
                    Write-Warning "DryRun: No changes to record in SQL table '$($table)' where '$($correlationProperty)'='$($correlationValue)'"
                }
                break
            }
        }
    }
}
finally {
    # Send results
    $result = [PSCustomObject]@{
        Success    = $success
        Auditlogs  = $auditLogs
        Account    = $account
 
        # Optionally return data for use in other systems
        ExportData = [PSCustomObject]@{
            $correlationProperty = $account.$correlationProperty
        } 
    }

    Write-Output $result | ConvertTo-Json -Depth 10
}