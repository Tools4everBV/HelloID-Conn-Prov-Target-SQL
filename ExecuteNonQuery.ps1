function ExecuteNonQuery($Query, $ConnectionString) {
    try {
        # Initialize connection and query information
        # Connect to the SQL server
        $SqlConnection = New-Object System.Data.SqlClient.SqlConnection;
        $SqlConnection.ConnectionString = $ConnectionString;
        $SqlCmd = New-Object System.Data.SqlClient.SqlCommand;
        $SqlCmd.Connection = $SqlConnection;
        
        #Execute SQL query
        $SqlCmd.CommandText = $query;        
        $SqlCmd.ExecuteNonQuery();
        return;
    }
    catch {
        Write-Error "Something went wrong while connecting to the SQL server";
        Write-Error $_.Exception.Message;
        Exit;
    }
}

$config = ConvertFrom-Json $configuration
$connectionString = "Data Source=$($config.server);Initial Catalog=$($config.database);User Id=$($config.user);Password=$($config.password);";

$query = "";

ExecuteNonQuery -Query $query -ConnectionString $connectionString;