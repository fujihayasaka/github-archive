# Use MySQ 8 Enums For Representing Image Type and Image Versions State

## Status
Accepted

***

## Context

During the initial implementation of the SQL data store layer for IMS we seperated the image definitions
and image versions for image types `Custom/Private` and `Curated/Public`. Therefore we did not yet need an `image_type` field. 

We also store the state of an `ImageVersion` during its import process in azure, i.e. `VersionImporting', 'VersionImportFailed` etc... 

We initially stored the `state` field as using the tinyint datatype. In the data access layer we needed to both convert a string const to its associated tinyint representation and back again.

Go has poor support for enums therefore we had a discussion around using the MySQL 8 enum type instead. This ADR documents that decisions and proposed schema changes. 

## Initial Implementation

### Our initial structure for attempting to represent enums in go code was as follows......

#### Schema

```sql
`state` tinyint NOT NULL COMMENT 'Image version state in azure gallery',
`osType` tinyint NOT NULL COMMENT 'Indicates Windows or Linux'
```
#### Associated Go Model Code

```go

type struct (
    ImageVersionState    int8
    OSType               int8
)

type ImageVersion struct {
    ......
    State             ImageVersionState
    ....
}

type ImageDefinition struct {
    ......
    OsType             OsType
    ....
}

const (
    VersionImporting    ImageVersionState = iota // 0
    VersionImportFailed                          // 1
    VersionProvisioning                          // 2
    VersionReady                                 // 3
    VersionDeleting                              // 4
)

const (
    Windows OsType = iota // 0
    Linux
)

func (s ImageVersionState) ToString() string {
    switch s {
    case VersionImporting:
        return "VersionImporting"
    case VersionImportFailed:
        return "VersionImportFailed"
   ......
}

```

## Proposal 

**Using a MySQL 8 enum for osType, imageVersion.State and imageDefinition.imageType fields...**

```sql
`image_type` ENUM ('curated', 'customer') NOT NULL
....
`os_type` ENUM('Linux','Windows') NOT NULL
....
`state` ENUM('VersionImporting', 'VersionImportFailed', 'VersionProvisioning', 'VersionReady', 'VersionDeleting') NOT NULL COMMENT 'Image version state'

.....

```

### Benefits
- MySQL stores the `ENUM` data type as a tinyint under the hood, but will resolve these to strings when reading from the database, there is no performance/optimization/storage concerns
- Our initial implementation was effectively doing this, but our conversion was happening in the service layer, we avoid the need for `toStrings` functions
- Human readable when inspecting the raw database
- Storing tinyints make sense if we can define these enums in the service layer code, however there is little to no Go support for the enum type 
- Added a new enum later on is only a modification to the table schema 

```sql

ALTER TABLE image_version 
    MODIFY COLUMN `state` 
        ENUM(
            'VersionImporting', 
            'VersionImportFailed', 
            'VersionProvisioning', 
            'VersionReady', 
            'VersionDeleting',
            'SuperNewVersionState'
            )
    NOT NULL
```

> NOTE
> 
> The existing enums MUST be provided in their previous order 

### Drawbacks

- Deleting an existing enum or modifying a name is a database migration as rows must be re-written (however this isn't something that will affect us and is just mentioned for completeness)
