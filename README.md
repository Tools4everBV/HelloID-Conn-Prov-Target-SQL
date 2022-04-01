# HelloID-Conn-Prov-Target-SQL

| :information_source: Information |
|:---------------------------|
| This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.       |

<br />

A generic HelloID provisioning target connector for executing Microsoft SQL queries.

## Instructions
- Use the ExecuteQuery.ps1 script whenever you need to perform a SELECT action in SQL, the table will be returned from the function call.
- Use the ExecuteNonQuery.ps1 script anywhere you need to perform non-SELECT (UPDATE, INSERT, etc) actions against a SQL database.

**Remember to fill in the $query variable with your nessecary SQL script**


# HelloID Docs
The official HelloID documentation can be found at: https://docs.helloid.com/