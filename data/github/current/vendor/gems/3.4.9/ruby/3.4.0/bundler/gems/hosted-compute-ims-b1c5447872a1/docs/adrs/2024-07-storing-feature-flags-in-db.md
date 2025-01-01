# Storing Image Feature Flags in Database

## Status
Proposed

## Context
We need to add support for curated image enablement by feature flag to the IMS service. Specifically, we can allow curated image enabled when feature flag is flipped. This will require modifications to severals APIs and change to the image definitions database schema. 

Current Schema: https://github.com/github/hosted-compute-ims/blob/main/schema/image_definition.sql

## Proposal 
### Option 1: Add new `feature_flag` Column
Modify `image_definition` table to include a new column `feature_flag`. This column will store the feature flag associate with each image definition. The `feature flag` can be null if the image is enabled or disabled globally. It will keeps the `enabled` column for boolean status.
#### Schema:
```
CREATE TABLE `image_definition` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `enabled` tinyint(1) NOT NULL DEFAULT '1' COMMENT 'Indicates whether this image is available for use',
  `feature_flag` varchar(128) DEFAULT NULL COMMENT 'Feature flag associated with the image',
  ...
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
```
#### API
CreateCuratedImageDefinitionRequest
```
message CreateCuratedImageDefinitionRequest {
  string name = 1 [
    (buf.validate.field).required = true,
    (buf.validate.field).string.pattern = "^[a-zA-Z0-9._-]{1,100}$"
  ];
  bool enabled = 2;
  string feature_flag = 3; // New field for feature flag
  shared.v1.OsType os_type = 4 [(buf.validate.field).enum.defined_only = true];
  shared.v1.Architecture architecture = 5 [(buf.validate.field).enum.defined_only = true];
}
```
UpdateCuratedImageDefinitionRequest
```
message CreateCuratedImageDefinitionRequest {
  string name = 1 [
    (buf.validate.field).required = true,
    (buf.validate.field).string.pattern = "^[a-zA-Z0-9._-]{1,100}$"
  ];
  bool enabled = 2;
  string feature_flag = 3; // New field for feature flag
  shared.v1.OsType os_type = 4 [(buf.validate.field).enum.defined_only = true];
  shared.v1.Architecture architecture = 5 [(buf.validate.field).enum.defined_only = true];
}
```
#### Considerations
- 👍 Keeps the semantics clear by separating the boolean state from the feature flag information
- 👍 Allows explicity handling of feature flags while maintaining existing boolean states
- 👎 May increase the complexity

### Option 2: Overloading `enabled` column with string: 
This approach involves reusing the existing `enabled` column but changing its type to a string. This way, the `enabled` column can store the specific feature flag name directly as well as the states "enabled" and "disabled"

#### Schema:
```
CREATE TABLE `image_definition` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `enabled` varchar(128) NOT NULL DEFAULT 'enabled' COMMENT 'Indicates whether this image is available for use, or the name of the feature flag if enabled per feature flag',
  ...
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
```
#### API
CreateCuratedImageDefinitionRequest
```
message CreateCuratedImageDefinitionRequest {
  string name = 1 [
    (buf.validate.field).required = true,
    (buf.validate.field).string.pattern = "^[a-zA-Z0-9._-]{1,100}$"
  ];
  string enabled = 2 [(buf.validate.field).string.pattern = "^(enabled|disabled|[a-zA-Z0-9._-]{1,128})$"]; // Can be "enabled", "disabled", or feature flag name
  shared.v1.OsType os_type = 3 [(buf.validate.field).enum.defined_only = true];
  shared.v1.Architecture architecture = 4 [(buf.validate.field).enum.defined_only = true];
}

```
UpdateCuratedImageDefinitionRequest
```
message UpdateCuratedImageDefinitionRequest {
  uint64 image_definition_id = 1 [(buf.validate.field).required = true];
  string name = 2 [
    (buf.validate.field).required = true,
    (buf.validate.field).string.pattern = "^[a-zA-Z0-9._-]{1,100}$"
  ];
  string enabled = 3 [(buf.validate.field).string.pattern = "^(enabled|disabled|[a-zA-Z0-9._-]{1,128})$"]; // Can be "enabled", "disabled", or feature flag name
}

```
#### Considerations
- 👍 Only change on column type and maintains a single column for both states and feature
- 👍 Allows storing specific feature flag names directly in the `enabled` column
- 👎 boolean state and feature flag name can still lead to some confusion

### Option 3: Separate table for feature flags
This approach involves creating a new table specifically for managing the relationship between image definitions and feature flags. The table would store mappings between image definitions and feature flags.
```
CREATE TABLE `image_feature_flag` (
  `image_definition_id` bigint unsigned NOT NULL COMMENT 'ID of the image definition',
  `feature_flag` varchar(128) NOT NULL COMMENT 'Feature flag associated with the image',
  PRIMARY KEY (`image_definition_id`, `feature_flag`),
  FOREIGN KEY (`image_definition_id`) REFERENCES `image_definition`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
```
#### API
Same as Option 1.

#### Considerations
- 👍 reduce the database complexity on image definitions
- 👎 requires join to retrieve feature flag information
- 👎 Joining tables can potentially slow down the performance as we scale up the datasets.

## Conclusion
I recommend Option 1 because adding a new feature_flag column provides clear separation of concerns and maintains flexibility without overloading the existing enabled column. This approach is straightforward to implement and understand, reducing the risk of misuse or confusion.
