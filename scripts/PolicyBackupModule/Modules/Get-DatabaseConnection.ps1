function Get-DatabaseConnection {
    param (
        [Parameter(Mandatory)][PSCustomObject]$Config
    )
 
    try {
        [void][System.Reflection.Assembly]::LoadWithPartialName("MySql.Data")
    } catch {
        throw "Failed to load MySql.Data. Run 'Install-Package MySql.Data' or download from https://dev.mysql.com/downloads/connector/net/"
    }
 
    $connectionString = "Server=$($Config.Database.Server);Port=$($Config.Database.Port);Database=$($Config.Database.DatabaseName);Uid=$($Config.Database.Username);Pwd=$($Config.Database.Password);SslMode=Required;"
 
    $connection = New-Object MySql.Data.MySqlClient.MySqlConnection
    $connection.ConnectionString = $connectionString
 
    try {
        $connection.Open()
        # Write-Output "Connected to MySQL database"
        return $connection
    } catch {
        throw ("Failed to connect to DB at {0}:{1} - {2}" -f $Config.Database.Server, $Config.Database.Port, $_.Exception.Message)
    }
}