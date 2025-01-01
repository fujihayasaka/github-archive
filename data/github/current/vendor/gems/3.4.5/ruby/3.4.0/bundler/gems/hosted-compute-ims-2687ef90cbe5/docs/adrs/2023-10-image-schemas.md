# Represent Both Custom and Curated Image Types In One Schema File

## Status
Accepted

***

## Context

During the initial implementation of the SQL data store layer for IMS we seperated the image definitions
and image versions for image types `Custom/Private` and `Curated/Public`. This resulted in four table schema files.
Given the two image types have nearly identical properties as well as the need to duplicate the API for operating on
different image types (due to the lack of Go support for inheritance/generics) [we had a discussion](https://github.com/github/hosted-compute-ims/discussions/75) around merging
both the image definition and image versions tables for both `Custom/Private` and `Curated/Public` images.

This ADR documents this decision and the proposed schema structure.

## Proposal

### Motivation to merge tables

- Properties were nearly identical for both image definitions
- The lack of go support to inheritance/generics meant huge duplication in the API for operating on both model types
- Error prone if a new field is added to an image definition as both schema files must be updated

### Motivation to use image type curated & customer over public & private

- The word private suggests a too restrictive definition of the use of the images. _Technically _ they are private. However this doesn't provide enough meaningful context on the intent of usage.
- Previously named public images are those provided by GitHub and GitHub-partners, the dictionary definition of the old name 'curated' is as follows

> of online content, merchandise, information, etc.) selected, organized, and presented using professional or expert knowledge.

- Given only the image-gen team and dotcom admins have write priveledge to these _public_ images this aligns perfectly with the statements _selected, organized, and presented using professional or expert knowledge._
- Using `Public & Private` together works because we're consistent in our lexicon. Both word makes reference to visbility but without context of intended usage
- If we didn't use the word public it doesn't make sense to use the word private, and vice versa
- Hence we settled on `Curated` & `Customer`

### A single `image_definition` table using a `image_type` field to distinguish image types

```sql
CREATE TABLE
    IF NOT EXISTS `image_definition` (
    -- Identity columns
    `id` BIGINT(20) unsigned NOT NULL AUTO_INCREMENT,
    `owner_id` VARCHAR(128) NOT NULL COLLATE utf8mb4_bin COMMENT 'github or github/github global_id of the owner of this image',
    `name` VARCHAR(256) NOT NULL COLLATE utf8mb4_0900_as_cs COMMENT 'Case sensitive name as assigned by github/owner of this image',
    `image_type` ENUM ('curated', 'customer') NOT NULL,
    -- State columns
    `enabled` BOOLEAN NOT NULL DEFAULT TRUE COMMENT 'Indicates whether this image is available for use',
    -- Metadata columns
    `os_type` ENUM('Linux','Windows') NOT NULL,
    `created_at` datetime (6) DEFAULT CURRENT_TIMESTAMP (6),
    `updated_at` datetime (6) DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP (6),
      -- Azure Resource ID columns
    `subscription_id` NVARCHAR (36) NULL,
    PRIMARY KEY (`id`),
    KEY `by_image_type` (`image_type`),
    KEY `by_owner_id_image_type` (`owner_id`, `image_type`),
    UNIQUE KEY `by_name_image_type` (`name`, `image_type`, `owner_id`) COMMENT 'Prevents duplicate names for Github-owned images but allows other image owners to use the same name as a Github owned image'
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

```

#### **Image type and OwnerId**

- The `image_type` field is used to identify whether this a Github-owned/partner image or a Customer image
- Customer images belong to an individual organization represented via an existing github/github global `owner_id` field
- For Github-owned images we use the constant `github` for the `owner_id` field, **using null would not be appropriate**:
  - This field must be populated for `image_type` customer, if we allow `NULL` for this field type we would need extra validation logic in the data access layer
  - When using a MySQL `unique` or `unique key` constraint on columns, `NULL` is treated as a non value therefore any constraint using the `owner_id` field would allow duplicate entries if `owner_id` was allowed to be null

#### **Unique Key Constraints**

**In a seperated schema definition case**......

... it suffices to provide constraints on the image definition tables for public/curated and private/customer respectively:

```sql
`id` BIGINT(20) unsigned NOT NULL AUTO_INCREMENT,
`name` VARCHAR(256),
PRIMARY KEY (`id`),
UNIQUE KEY `by_name` (`name`),
```

- For Github-owned images, the name must be unique across all image definitions as we only allow one `Ubuntu20`
- Therefore we use a `by_name` unique constraint

```sql
`id` BIGINT(20) unsigned NOT NULL AUTO_INCREMENT,
`name` VARCHAR(256),
`owner_id` VARCHAR(128) NOT NULL,
PRIMARY KEY (`id`),
UNIQUE KEY `by_definition_name_owner_id` (`name`, `owner_id`)
```

- For Customer images the `name` of the image definition must be unique across that owner, but not between owners.
  - For example we should allow both owner `k_xp` and `o_x2` to have an image definition named `CustomUbuntu20` but we should not allow owner `k_xp` to have two `CustomUbuntu20`'s


**Merging definitions case...**

In merging the image definitions for the two types we must meet the following criteria
- For Github-owned images we must prevent duplicate name entries
- For Customer owned images we must prevent duplicate name entries per customer
- For Customer owned image we must allow duplicate names across customers
- We should allow both a Github-owned image and Customer image to share a name

To satisfy the above we provide a unique constraint....

```sql
UNIQUE KEY `by_name_image_type` (`name`, `image_type`, `owner_id`)
```

### A single `image_version` table with a foreign key

```sql
CREATE TABLE
    IF NOT EXISTS `image_version` (
    -- Identity columns
    `id` BIGINT(20) unsigned NOT NULL AUTO_INCREMENT,
    `version` nvarchar (32) NOT NULL COMMENT 'Version of the image',
    `image_definition_id` BIGINT(20) unsigned NOT NULL,
    -- State columns
    `state` ENUM('VersionImporting', 'VersionImportFailed', 'VersionProvisioning', 'VersionReady', 'VersionDeleting') NOT NULL COMMENT 'Image version state',
    `enabled` BOOLEAN NOT NULL DEFAULT TRUE COMMENT 'Indicates whether this image version is available for use',
    -- Metadata columns
    `created_at` datetime (6) DEFAULT CURRENT_TIMESTAMP (6),
    `updated_at` datetime (6) DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP (6),
    PRIMARY KEY (`id`),
    UNIQUE KEY `by_version_image_definition_id` (`version`, `image_definition_id`),
    FOREIGN KEY (`image_definition_id`) REFERENCES `image_definition` (`id`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;
```

#### Unique Key Constraint

```sql
UNIQUE KEY `by_version_image_definition_id` (`version`, `image_definition_id`),
```

- Prevents duplicate versions for an associated image versions

#### Foreign Key Constraint

```sql
FOREIGN KEY (`image_definition_id`) REFERENCES `image_definition` (`id`)
```

- Ensures data integrity at the DB level
- Prevents an image version being added if the provided `image_definition_id` does not exist
- Prevents deleting an `image_definition` if it has an associated image version.
