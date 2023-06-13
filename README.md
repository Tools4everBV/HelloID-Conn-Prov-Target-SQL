# HelloID-Conn-Prov-Target-SQL

| :information_source: Information |
|:---------------------------|
| This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.       |
<br />
<p align="center"> 
  <img src="https://www.github.com/test.png">
</p>

## Versioning
| Version | Description | Date |
| - | - | - |
| 1.0.0   | Updated create,update,delete examples | 2022/11/17  |
| 0.9.0   | Initial release | 2022/04/01  |

<!-- TABLE OF CONTENTS -->
## Table of Contents
- [HelloID-Conn-Prov-Target-SQL](#helloid-conn-prov-target-sql)
  - [Versioning](#versioning)
  - [Table of Contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Getting started](#getting-started)
    - [Connection settings](#connection-settings)
    - [Remarks](#remarks)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)


## Introduction
_HelloID-Conn-Prov-Target-SQL is a _target_ connector. This is ageneric HelloID provisioning target connector for executing Microsoft SQL queries. The HelloID connector allows you to writing,updating and deleting rows in Microsoft SQL database table.

> Note that this connector is generic and therfore only has limited examples.
 - > We only have examples for create,update and delete, since enable/disable are just an update action with a different account object.

The HelloID connector consists of the template scripts shown in the following table.

| Action                          | Action(s) Performed                           | Comment   | 
| ------------------------------- | --------------------------------------------- | --------- |
| create.ps1                      | Correlate or create SQL record                |           |
| update.ps1                      | Update SQL record                             |           |
| delete.ps1                      | Delete SQL record                             | Be careful when implementing this! There is no way to restore deleted records (apart from a backup and restore).  |

<!-- GETTING STARTED -->
## Getting started
### Connection settings
The following settings are required to connect to the API.

| Setting               | Description                                                       | Mandatory   |
| --------------------- | ----------------------------------------------------------------- | ----------- |
| Connection string       | The connection string used to connect to the SQL database. Must include Initial Catalog                               | Yes         |
| Table             | The table in which the records reside                   | Yes         |
| Update when correlating and mapped data differs from data in SQL DB         | When toggled, the mapped properties will be updated in the create action (not just correlate).               | No         |
| Toggle debug logging | When toggled, extra logging is shown. Note that this is only meant for debugging, please switch this off when in production. | No         |

### Remarks
> We can only set existing rows of an existing database table. We cannot create new rows during the actions.

## Getting help
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/hc/en-us/articles/360012558020-Configure-a-custom-PowerShell-target-system) pages_

> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_

## HelloID docs
The official HelloID documentation can be found at: https://docs.helloid.com/
