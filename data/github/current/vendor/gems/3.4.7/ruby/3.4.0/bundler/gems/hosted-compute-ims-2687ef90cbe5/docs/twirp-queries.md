# Twirp API queries

`script/twirpcurl` is a wrapper around curl which simplifies making requests to the twirp API:
```
Usage: echo '<json>' | script/twirpcurl <service> <method>
Available services:
    - ping              - check if the server is alive
    - images            - customers API
    - admin             - admin API
    - internal          - internal hosted compute services API

Examples:
    script/twirpcurl ping
    script/twirpcurl images ListCuratedImageDefinitions
    script/twirpcurl admin ListCuratedImageDefinitions
    script/twirpcurl internal GetImageDetails
    echo '{ "image_definition_id": 3 }' | script/twirpcurl images GetCuratedImageDefinition
    echo '{ "name": "myImage3", "os_type": "Linux", "architecture": "Arm64" }' | script/twirpcurl admin CreateCuratedImageDefinition
    echo '{ "image_definition_id": 63, "version": "1.0.0", "source_vhd_url": "http://myurl" }' | script/twirpcurl admin CreateCuratedImageVersion
    echo '{ "image_key": { "source": "Curated", "id": 1, "version": "1.0.0" } }' | script/twirpcurl internal GetImageDetails

```

By default, script is configured to call local environment with disabled auth.

## Calling the API
Prerequisites:
1. Connect to [production shell](https://thehub.github.com/security/security-operations/production-shell-access/).
2. Download `script/twirpcurl` script to shell VM:
    - `$ curl --output ims-curl.sh https://raw.githubusercontent.com/github/hosted-compute-ims/main/script/twirpcurl --header "Authorization: Bearer $HUBOT_GITHUB_TOKEN"`
2. Get IMS HMAC secret from vault:
    - `$ . vault-login`

### Make API call to `lab`

Steps:
1. Export the lab HMAC key
    - `export IMS_HMAC=$(vault-secret --application hosted-compute-ims --environment lab --key HOSTED_COMPUTE_IMS_HMAC_KEY)`
3. Set IMS URL:
    - `$ export IMS_HOST="https://hosted-compute-ims-lab.service.iad.github.net"`
4. Run command. Examples:
    - `$ bash ims-curl.sh admin ListCuratedImageDefinitions`
    - `$ echo '{ "owner_id": "test" }' | bash ims-curl.sh images ListCustomerImageDefinitions`

### Production API calls

> [!CAUTION]  
> Making direct API requests to production is not recommended because it is unsafe. But sometimes, it is required.

> [!WARNING]  
> When perform Create or Update operations on production, keep on kind that IMS uses PUT API approach. It means all that caller should pass the full model in its request body.
> Any missed property will be treated as NULL and updated to default value. 

Additional Prerequisites:
1. Export the prod HMAC key
    - `$ export IMS_HMAC=$(vault-secret --application hosted-compute-ims --environment production --key HOSTED_COMPUTE_IMS_HMAC_KEY)`

#### Make API call to `production/canary`

This is useful if you have hit 

1. Set IMS URL:
    - `$ export IMS_HOST="https://hosted-compute-ims-production-canary.service.iad.github.net"`
2. Run command. Examples:
    - `$ bash ims-curl.sh admin ListCuratedImageDefinitions`
    - `$ echo '{ "owner_id": "test" }' | bash ims-curl.sh images ListCustomerImageDefinitions`

#### Make API call to `production`

Steps:
1. Set IMS URL:
    - `$ export IMS_HOST="https://hosted-compute-ims-production.githubapp.com"`
2. Run command. Examples:
    - `$ bash ims-curl.sh admin ListCuratedImageDefinitions`
    - `$ echo '{ "owner_id": "test" }' | bash ims-curl.sh images ListCustomerImageDefinitions`

## Health

#### `/_ping`

```bash
script/twirpcurl ping
```

## Customer API

#### `/ListCuratedImageDefinitions`

```bash
echo '{ "owner": { "global_id": "kv_3xy" }, "include_disabled": true }' | script/twirpcurl images ListCuratedImageDefinitions
```

#### `/GetCuratedImageDefinition`

```bash
echo '{ "image_definition_id": 5, "owner": { "global_id": "kv_3xy" } }' | script/twirpcurl images GetCuratedImageDefinition
```

#### `/ListCuratedImageVersions`

```bash
echo '{ "image_definition_id": 5, "owner": { "global_id": "kv_3xy" } }' | script/twirpcurl images ListCuratedImageVersions
```

#### `/GetCuratedImageVersion`

```bash
echo '{ "image_definition_id": 5, "version": "1.0.1", "owner": { "global_id": "kv_3xy" } }' | script/twirpcurl images GetCuratedImageVersion
```

#### `/ListCustomerImageDefinitions`

```bash
echo '{ "owner": { "global_id": "kv_3xy" } }' | script/twirpcurl images ListCustomerImageDefinitions
```

#### `/GetCustomerImageDefinition`

```bash
echo '{ "owner": { "global_id": "kv_3xy" }, "image_definition_id": 8 }' | script/twirpcurl images GetCustomerImageDefinition
```

#### `/ListCustomerImageVersions`

```bash
echo '{ "owner": { "global_id": "kv_3xy" }, "image_definition_id": 8 }' | script/twirpcurl images ListCustomerImageVersions
```

#### `/GetCustomerImageVersion`

```bash
echo '{ "owner": { "global_id": "kv_3xy" }, "image_definition_id": 8, "version": "1.0.0" }' | script/twirpcurl images GetCustomerImageVersion
```

#### `/CreateCustomerImageDefinition`

```bash
echo '{ "owner": { "global_id": "kv_3xy" }, "name": "image1", "os_type": "Linux", "architecture": "Arm64" }' | script/twirpcurl images CreateCustomerImageDefinition
```

#### `/UpdateCustomerImageDefinition`

```bash
echo '{ "owner": { "global_id": "kv_3xy" }, "image_definition_id": 77, "name": "image2" }' | script/twirpcurl images UpdateCustomerImageDefinition
```

#### `/DeleteCustomerImageDefinition`

```bash
echo '{ "owner": { "global_id": "kv_3xy" }, "image_definition_id": 77 }' | script/twirpcurl images DeleteCustomerImageDefinition
```

#### `/CreateCustomerImageVersion`

```bash
echo '{ "owner": { "global_id": "kv_3xy" }, "image_definition_id": 76, "version": "1.0.0", "source_vhd_url": "https://url.com" }' | script/twirpcurl images CreateCustomerImageVersion
```

#### `/DeleteCustomerImageVersion`

```bash
echo '{ "owner": { "global_id": "kv_3xy" }, "image_definition_id": 76, "version": "1.0.0", "source_vhd_url": "https://url.com" }' | script/twirpcurl images DeleteCustomerImageVersion
```

## Admin API

#### `/ListCuratedImageDefinitions`

```bash
script/twirpcurl admin ListCuratedImageDefinitions
```

#### `/GetCuratedImageDefinition`

```bash
echo '{ "image_definition_id": 63 }' | script/twirpcurl admin GetCuratedImageDefinition
```

#### `/ListCuratedImageVersions`

```bash
echo '{ "image_definition_id": 63 }' | script/twirpcurl admin ListCuratedImageVersions
```

#### `/GetCuratedImageVersion`

```bash
echo '{ "image_definition_id": 63, "version": "1.0.0" }' | script/twirpcurl admin GetCuratedImageVersion
```

#### `/CreateCuratedImageDefinition`

```bash
echo '{ "name": "image1", "os_type": "Linux", "architecture": "Arm64", "enabled": true, "owner_id": "github" }' | script/twirpcurl admin CreateCuratedImageDefinition
```

#### `/CreateCuratedImageDefinition` which supports image generation

```bash
echo '{ "name": "image1", "os_type": "Linux", "architecture": "Arm64", "enabled": true, "owner_id": "github", "is_image_generation_supported": true }' | script/twirpcurl admin CreateCuratedImageDefinition
```

#### `/CreateCuratedImageDefinition` behind feature flag

```bash
echo '{ "name": "test-with-feature-flag", "os_type": "Linux", "architecture": "X64", "feature_flag": "ims_canary_curated_images", "owner_id": "github" }' | script/twirpcurl admin CreateCuratedImageDefinition
```

#### `/UpdateCuratedImageDefinition`

```bash
echo '{ "image_definition_id": 80, "name": "image2", "enabled": false }' | script/twirpcurl admin UpdateCuratedImageDefinition
```

#### `/DeleteCuratedImageDefinition`

```bash
echo '{ "image_definition_id": 80 }' | script/twirpcurl admin DeleteCuratedImageDefinition
```

#### `/CreateCuratedImageDefinitionPointer`

```bash
echo '{ "name": "MyPointer", "enabled": true, "points_to_image_definition_id": 3 }' | script/twirpcurl admin CreateCuratedImageDefinitionPointer
```

#### `/UpdateCuratedImageDefinitionPointer`

```bash
echo '{ "image_definition_id": 4, "name": "MyPointer", "enabled": false, "points_to_image_definition_id": 3 }' | script/twirpcurl admin UpdateCuratedImageDefinitionPointer
```

#### `/DeleteCuratedImageDefinitionPointer`

```bash
echo '{ "image_definition_id": 4 }' | script/twirpcurl admin DeleteCuratedImageDefinitionPointer
```

#### `/CreateCuratedImageVersion`

```bash
echo '{ "image_definition_id": 1, "version": "2.0.0", "enabled": true, "source_vhd_url": "https://url.com" }' | script/twirpcurl admin CreateCuratedImageVersion
```

#### `/UpdateCuratedImageVersion`

```bash
echo '{ "image_definition_id": 1, "version": "1.0.0", "enabled": false }' | script/twirpcurl admin UpdateCuratedImageVersion
```

#### `/DeleteCuratedImageVersion`

```bash
echo '{ "image_definition_id": 1, "version": "1.0.0" }' | script/twirpcurl admin DeleteCuratedImageVersion
```

## internal API

These do not use an hmac, but instead use a oidc token from the runner service.
The [data folder](https://github.com/github/hosted-compute-ims/tree/main/data) has details on valid issuers for each environment.

#### `/GetImageDetails`

```bash
echo '{ "image_key": { "source": "Curated", "id": 1, "version": "latest" }, "owner": { "global_id": "kv_3xy", "stamp": "dotcom" } }' | script/twirpcurl internal GetImageDetails
```

#### `/GetImageReference`

```bash
echo '{ "image_key": { "source": "Curated", "id": 1, "version": "1.0.0" } }' | script/twirpcurl internal GetImageReference
```

