# Handling the Concept of Latest for Curated Images

## Status
Accepted

***

## Context

### Purpose

The purpose of this document is to outline how we can support the concept of Windows and Ubuntu latest within the Image Management Service, such that users can pin their pools to a particular image definition, or latest. Should the latest image be updated, user pools should be re-imaged to use the new latest image definition.

### Background

Standard Runners support the concept of `ubuntu-latest` and `windows-latest`. Users can provide this label to their workflow `runs-on` in order to run their workflows against the latest image for Windows and Ubuntu.

We introduced a similar concept to the Runner service. Allowing users upon provisioning a pool to select the latest image for either Windows or Ubuntu. As with all Curated images, we hardcode this mapping of latest to an existing Curated image id within the [CuratedImagesService](https://github.com/github/actions-dotnet/blob/main/Runner/Service/Server/Images/CuratedImagesService.cs#L29).


### Requirements

- The list of currently supported Curated images returned to dotcom should include a latest option for each OS and architecture pairing
    - Ubuntu X64/Arm64
    - Windows X64/Arm64
- Ability to mark a an image as latest
- Ability to enable/disable a latest image definition
- The display name for this image definition should indicate is it latest, e.g. `Ubuntu 2022` vs `Ubuntu 2022 (Latest)`
- When a new image is released, a solution flexible enough for extension later such that we can roll-out migration to a % of customers (this may or may not be required but should be considered)
- This returned latest image definition should allow us to easily resolve the referenced image definition
- A list or get image version request should return the versions associated with the image definition marked as latest

## Proposal

### Storing Latest Image Definition Within the DB

Introduce a nullable field to the `ImageDefinition` E.g.

```sql
CREATE TABLE
    IF NOT EXISTS `image_definition` (
    .....
    -- Pointer columns
    `points_to_image_definition_id` BIGINT(20) unsigned DEFAULT NULL COMMENT 'If populated the PK (id) of an existing image definition with represents latest. Therefore this db entry should be treated as a pointer',
    .....
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;
```

All other fields should simply be duplicated from the referenced image definition with the exception of `name` which will most likely contain the word `(Latest)`. For example the reference to an image definition with name `Ubuntu 2022` will have name `Ubuntu 2022 (Latest)`

Utilizing a single field has several benefits/purposes
1. Indicates this image definition represents latest and is simply a pointer to an existing image definition and should be resolved to that
2. Allows us to use our existing table:
    - Maintains simplicity of the `ListCuratedImages` endpoint/response as it just returns additional entries within the DB
    - No additional logic required when building the API for the Runner Config Service, we just provide the auto incremented ID as standard. Then IMS wil simply check whether this field is populated in order to resolve the correct image reference.
    - Easier to maintain data integrity, an entry in the image definition table for latest cannot be added unless the supplied image definition exists
    - A new table would mean several additional API endpoints on the Customer/Public API to work with a different table/data model, which would increase complexity and reduce maintainability
3. A latest record will have a stable auto incremented ID, this ID is passed to runner/runner config service and it treated like any other image definition id, whereby the responsibility to resolve this to the correct image reference lies with IMS. It means should a new version be released existing pools will simply be re-imaged with the reference latest ID.

### How will an Image Definition Record be identified as Latest for Each OS

The combination of a non null `points_to_image_definition_id`, `OS`, and `Arch` will uniquely identify that record as the pointer to the latest image definition for each operating system and architecture.

```
+-----+----------+-----------------------------+------------+---------+---------+--------------+----------------------------+------------+-----------------------+-------------------------------+
| id  | owner_id | name                        | image_type | enabled | os_type | architecture | created_at                 | updated_at | azure_subscription_id | points_to_image_definition_id |
+-----+----------+-----------------------------+------------+---------+---------+--------------+----------------------------+------------+-----------------------+-------------------------------+
| 118 | github   | Ubuntu 2022 (Latest)        | Curated    |       1 | Linux   | X64          | 2024-02-14 13:44:28.041164 | NULL       |                  NULL |                             3 |
| 120 | github   | Ubuntu Arm64 2022 (Latest)  | Curated    |       1 | Linux   | Arm64        | 2024-02-14 13:45:37.581966 | NULL       |                  NULL |                             2 |
| 121 | github   | Windows Arm64 2022 (Latest) | Curated    |       1 | Windows | Arm64        | 2024-02-14 13:46:46.829643 | NULL       |                  NULL |                             1 |
| 122 | github   | Windows 2022 (Latest)       | Curated    |       1 | Windows | X64          | 2024-02-14 13:47:00.116954 | NULL       |                  NULL |                             5 |
+-----+----------+-----------------------------+------------+---------+---------+--------------+----------------------------+------------+-----------------------+-------------------------------+
```

> Note 📓
>
> You may consider/suggest using two fields to denote a record is a pointer, e.g. `is_latest BOOLEAN DEFAULT FALSE` and `latest_image_id DEFAULT NULL`
>
> Whether a record is a pointer can be answered in one field. Two fields is more infrastructure/complication as data integrity between the two fields would need to be maintained. Additionally behind the scenes a query to `NOT NULL` is a seek. Whereas a query to check for negative/positive conditions is a table scan, unless an index is created.

### The API for Working with a Latest Image Definition

### Customer API
On retrieving all curated image image definitions, Ubuntu/Windows latest will be returned via dotcom/public api as with any other image definition. However for image versions we should modify the existing customer api endpoints:

- `ListCuratedImageVersions(image_definition_id)` - if image_definition_id is a pointer, return image versions from resolved reference
- `GetCuratedImageVersion(image_definition_id, version)` if image_definition_id is a pointer, return image versions from resolved reference

### Admin API
Creation/deletion/updates to latest image definitions should be entirely an admin action.

There are a few options detailed below for modifying/adding to the api and the choice depends on how much we wish to explicitly mark an image definition as latest to the client and how much responsibility we wish to delicate to the calling client vs abstract this within the image service.

#### Option 1: Using Existing CREATE and UPDATE CRUD API

CREATE
- Introduce nullable field `latest_image_definition_id` to `CreateCuratedImageDefinition`
- Presence of this field should indicate to the server that this is a pointer and to create a new image definition copying the fields of the existing image definition
- Assume calling API will provide `name` with some reference to `Latest`
- If a record already exists in the database then return an error (changing the reference image definition on a new release should be the responsibility of the UPDATE operation)

E.g. On

```yaml
{
  name: "Ubuntu 2022 (Latest)"
  os: "Linux"
  architecture: "X64"
  points_to_image_definition_id: 5
}
```

Behind the scenes we would need to perform a check such as...

```sql
-- This a RAW SQL is purely an illustrative example NOT a proposal for the server side query
SELECT EXISTS (SELECT * from image_definition WHERE latest_image_definition_id IS NOT NULL AND os_type = "Linux" AND architecture = "X64");
```

UPDATE
- On the release of a new Ubuntu version, i.e. `Ubuntu Super` for `linux X64`
- Introduce nullable field `points_to_image_definition_id` to `UpdateCuratedImageDefinitionRequest`
- The presence of this field indicates we expect the request to be an update to our pointer image definition, where the provided `image_definition_id` is the ID of a pointer

e.g

```yaml
{
  image_definition_id: 5 // ID of pointer record
  name: "Ubuntu Super (Latest)"
  points_to_image_definition_id: 6 // ID of record Ubuntu Super
}
```

#### Considerations
- :thumbsup: Uses existing server side endpoints
- :thumbsup: Treats a pointer like any other image definition record from the client perspective
- :thumbsdown: Additional validation logic and error handling needs to be introduced to the server to handle the presence of this nullable field, thereby potentially reducing clarity of existing functionality by introducing more control flow logic
- :thumbsdown: Requires the client to perform a List/Get before any call to Create/Update to retrieve the correct image definition to be marked as latest
- :thumbsdown: Requires the client to programmatically build the name from the existing record to introduce a latest suffix
- :thumbsdown: It overcomplicates the update endpoint. We'd need logic to check the passed ID's to determine when we're simply updating the name/enabled of an image definition, vs updating the pointer.
  - E.g. if `latest_image_id` is provided, then we must validate `image_definition_id` is the pointer record etc..

#### Option 2: Add Separate Admin Endpoints for Working with Latest

**Additional Admin Endpoints**

I'm using proto here as an illustrative example, IT'S NOT necessarily a suggestion of the final form...

**On Create**

```proto
rpc CreateLatestCuratedImageDefinition(CreateCuratedImageDefinitionRequest) returns (CreateCuratedImageDefinitionResponse) {}

message CreateLatestCuratedImageDefinitionRequest {
  string name = 1 [
    (buf.validate.field).required = true,
    (buf.validate.field).string.pattern = "^[a-zA-Z0-9._-]{1,100}$"
  ];
  bool enabled = 2;
  uint64 points_to_image_definition_id = 3 [(buf.validate.field).required = true];
}
```

- The server will validate `points_to_image_definition_id` is an existing `ImageDefinition` NOT a pointer record
- The server will validate that a pointer record DOES NOT already exist for this image definition (This should be an UPDATE operation)

**On Update**

```proto

rpc UpdateLatestCuratedImageDefinition(UpdateCuratedImageDefinitionRequest) returns (UpdateCuratedImageDefinitionResponse) {}

message UpdateLatestCuratedImageDefinitionRequest {
  uint64 image_definition_id = 1 [(buf.validate.field).required = true];
  string name = 2 [
    (buf.validate.field).required = true,
    (buf.validate.field).string.pattern = "^[a-zA-Z0-9._-]{1,100}$"
  ];
  bool enabled = 3;
  uint64 points_to_image_definition_id = 4 [(buf.validate.field).required = true];
}
```

- The server will validate `image_definition_id` is an existing `ImageDefinition` and IS a pointer record
- The server will validate `points_to_image_definition_id` is an existing `ImageDefinition` and NOT a pointer record

**On Delete**

```proto
rpc DeleteLatestCuratedImageDefinition(DeleteCuratedImageDefinitionRequest) returns (DeleteCuratedImageDefinitionResponse) {}

message DeleteLatestCuratedImageDefinitionRequest {
    uint64 image_definition_id = 1 [(buf.validate.field).required = true];
}
```

- The server will validate `image_definition_id` is an existing `ImageDefinition` and IS a pointer record

### Handling Enabled
- A latest record should only be shown to the Customer/dotcom API if and only if both the pointer and reference image definition have `enabled = true`

### Handling ImageDefinition Deletion
- If a Curated Image definition is deleted where that image definition is referenced as latest we should ensure we delete both

## Conclusions

I recommend Option 2 for the following reasons:

- :thumbsup: Keeps the responsibility entirely with IMS, the client shouldn't have to worry/care/deal with error responses borne of validation logic checking whether ids are pointers or not
- :thumbsup: Additional endpoints sets clear boundary of responsibility as well as intent rather than mixing this within existing endpoints with specific control flow logic and increasing our error responses
- :thumbsup: Other endpoints can work exactly the same way

## Future Extensions

- If latest is currently set to `Ubuntu 2022` and `Ubuntu 2024` is released, for example, we may wish to slow the migration of pools e.g set 50% of users to this new image

Our solution is flexible enough such that we can extend the new field to a json object for example

```
+----+----------+-----------------------+------------+---------+---------+--------------+----------------------------+------------+-----------------------+------------------------------------------------------+
| id | owner_id | name                  | image_type | enabled | os_type | architecture | created_at                 | updated_at | azure_subscription_id | latest                                               |
+----+----------+-----------------------+------------+---------+---------+--------------+----------------------------+------------+-----------------------+------------------------------------------------------+
|  1 | github   | Ubuntu 22.04 (Latest) | Curated    |       1 | Linux   | X64          | 2024-01-22 11:42:00.975310 | NULL       |                     1 | {"new": 6, "current": 5, "migration_percentage": 50} |
+----+----------+-----------------------+------------+---------+---------+--------------+----------------------------+------------+-----------------------+------------------------------------------------------+

+--------------------------------------------------------------+
| json_pretty(latest)                                          |
+--------------------------------------------------------------+
| {
  "new": 6,
  "current": 5,
  "migration_percentage": 50
} |
+--------------------------------------------------------------+
```





