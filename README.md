# HelloID-Conn-Prov-Target-SQL

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
   <img src="https://www.tools4ever.nl/connector-logos/microsoftsql-logo.png">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-SQL](#helloid-conn-prov-target-SQL)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Getting started](#getting-started)
    - [Provisioning PowerShell V2 connector](#provisioning-powershell-v2-connector)
      - [Correlation configuration](#correlation-configuration)
      - [Field mapping](#field-mapping)
    - [Connection settings](#connection-settings)
    - [Prerequisites](#prerequisites)
    - [Remarks](#remarks)  
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-SQL_ is a _target_ connector. This is a generic HelloID provisioning target connector for executing Microsoft SQL queries. The HelloID connector allows you to writing,updating and deleting rows in Microsoft SQL database table.

The following lifecycle actions are available:

| Action             | Description                                                                                                                              |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------------------- |
| create.ps1         | PowerShell _create_ lifecycle action                                                                                                     |
| delete.ps1         | PowerShell _delete_ lifecycle action                                                                                                     |
| disable.ps1        | PowerShell _disable_ lifecycle action                                                                                                    |
| enable.ps1         | PowerShell _enable_ lifecycle action                                                                                                     |
| update.ps1         | PowerShell _update_ lifecycle action                                                                                                     |
| configuration.json | Default _[Configuration.json](https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-V2-Template/blob/main/target/configuration.json)_ |
| fieldMapping.json  | Default _[FieldMapping.json](https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-V2-Template/blob/main/target/fieldMapping.json)_   |

## Getting started

### Provisioning PowerShell V2 connector

#### Correlation configuration

The correlation configuration is used to specify which properties will be used to match an existing account within _SQL_ to a person in _HelloID_.

To properly setup the correlation:

1. Open the `Correlation` tab.

2. Specify the following configuration:

   | Setting                   | Value                             |
   | ------------------------- | --------------------------------- |
   | Enable correlation        | `True`                            |
   | Person correlation field  | `PersonContext.Person.ExternalId` |
   | Account correlation field | `EmployeeId`                      |

> [!TIP] 
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.

#### Field mapping

The field mapping can be imported by using the _fieldMapping.json_ file.

### Connection settings

The following settings are required to connect to the SQL Server.

| Setting              | Description                                                                                                                  | Mandatory |
| -------------------- | ---------------------------------------------------------------------------------------------------------------------------- | --------- |
| ConnectionString     | The connection string used to connect to the SQL database. Must include Initial Catalog                                      | Yes       |
| Table                | The table in which the records reside                                                                                        | Yes       |

### Prerequisites

### Remarks

## Getting help

> [!TIP] 
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

> [!TIP] 
> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
