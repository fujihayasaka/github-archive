# Staging Curls
- [Staging Curls](#staging-curls)
  - [CreateOrganizationPolicy](#createorganizationpolicy)
  - [GetOrganizationPolicy](#getorganizationpolicy)
  - [CreateEnterprisePolicy](#createenterprisepolicy)
  - [GetEnterprisePolicy](#getenterprisepolicy)
  - [AddLicensesToEnterprisePolicy](#addlicensestoenterprisepolicy)
  - [DeleteLicensesFromEnterprisePolicy](#deletelicensesfromenterprisepolicy)
  - [CreateRepositoryPolicy](#createrepositorypolicy)
  - [GetRepositoryPolicy](#getrepositorypolicy)

Example curls for staging twirp API

The IDs in the example below are for github and the osslicensecompliance repo.

* TODO: look up enterprise ID
* github org is 9919
* osslicensecompliance repo is 878404792

## CreateOrganizationPolicy

```sh
curl -0 -v -X POST \
https://osslicensecompliance-twirp-staging.service.iad.github.net/twirp/oss_license_compliance.v0.LicenseCompliance/CreateOrganizationPolicy \
-H "Content-Type: application/json" \
--data-binary @- << EOF
{
    "organization_id": 9919,
        "licenseLists": [
        {
            "name": "default",
            "allowed": ["MIT"]
        }
        ],
        "packages": [
        {
            "package_manager": "PACKAGE_MANAGER_NPM",
            "name": "lodash",
            "action": "PACKAGE_ACTION_ALLOWED",
            "reason": "reason",
            "extra_allowed_spdx_ids": ["MIT"],
            "expires":"2025-12-09T15:44:31.894Z"
        }
        ],
        "curations": [
        {
            "package_manager": "PACKAGE_MANAGER_NPM",
            "package_name": "lodash",
            "reason": "curation-reason",
            "extra_allowed_spdx_ids": ["MIT"],
            "new_license": "BSD-Clause-3",
            "expires":"2025-12-09T15:44:31.894Z"
        }
        ]
}
EOF
```

## GetOrganizationPolicy

```sh
curl -0 -v -X POST \
https://osslicensecompliance-twirp-staging.service.iad.github.net/twirp/oss_license_compliance.v0.LicenseCompliance/GetOrganizationPolicy \
-H "Content-Type: application/json" \
--data-binary @- << EOF
{
    "organization_id": 9919
}
EOF
```

## CreateEnterprisePolicy

```sh
curl -0 -v -X POST \
https://osslicensecompliance-twirp-staging.service.iad.github.net/twirp/oss_license_compliance.v0.LicenseCompliance/CreateEnterprisePolicy \
-H "Content-Type: application/json" \
--data-binary @- << EOF
{
    "enterprise_id": 200,
    "licenseLists": [
        {
            "name": "policy-name",
            "allowed": ["MIT"]
        }
    ],
    "packages": [
        {
            "package_manager": "PACKAGE_MANAGER_NPM",
            "name": "lodash",
            "action": "PACKAGE_ACTION_ALLOWED",
            "reason": "reason"
        }
    ],
    "curations": [
        {
            "package_manager": "PACKAGE_MANAGER_NPM",
            "package_name": "lodash",
            "reason": "curation-reason",
            "extra_allowed_spdx_ids": ["MIT"],
            "new_license": "BSD-Clause-3",
            "expires":"2025-12-09T15:44:31.894Z"
        }
    ]
}
EOF
```

## GetEnterprisePolicy

```sh
curl -0 -v -X POST \
https://osslicensecompliance-twirp-staging.service.iad.github.net/twirp/oss_license_compliance.v0.LicenseCompliance/GetEnterprisePolicy \
-H "Content-Type: application/json" \
--data-binary @- << EOF
{
    "enterprise_id": 200
}
EOF
```

## AddLicensesToEnterprisePolicy

```sh
curl -0 -v -X POST \
https://osslicensecompliance-twirp-staging.service.iad.github.net/twirp/oss_license_compliance.v0.LicenseCompliance/AddLicensesToEnterprisePolicy \
-H "Content-Type: application/json" \
--data-binary @- << EOF
{
    "enterprise_id": 200,
    "spdx_ids": ["MIT", "Apache-2.0"],
    "context": "distributed"
}
EOF
```

## DeleteLicensesFromEnterprisePolicy

```sh
curl -0 -v -X POST \
https://osslicensecompliance-twirp-staging.service.iad.github.net/twirp/oss_license_compliance.v0.LicenseCompliance/DeleteLicensesFromEnterprisePolicy \
-H "Content-Type: application/json" \
--data-binary @- << EOF
{
    "enterprise_id": 200,
    "spdx_ids": ["Apache-2.0"],
    "context": "distributed"
}
EOF
```

## CreateRepositoryPolicy

```sh
curl -0 -v -X POST \
https://osslicensecompliance-twirp-staging.service.iad.github.net/twirp/oss_license_compliance.v0.LicenseCompliance/CreateRepositoryPolicy \
-H "Content-Type: application/json" \
--data-binary @- << EOF
{
    "repository_id": 878404792,
    "organization_id": 9919,
    "lock_files_only": true,
    "root_manifests_only": true,
    "additional_manifests": ["tools/go.mod"],
    "repository_licenses": ["BSD-3-Clause"],
    "packages": [
    ]
}
EOF
```

## GetRepositoryPolicy

```sh
curl -0 -v -X POST \
https://osslicensecompliance-twirp-staging.service.iad.github.net/twirp/oss_license_compliance.v0.LicenseCompliance/GetRepositoryPolicy \
-H "Content-Type: application/json" \
--data-binary @- << EOF
{
    "repository_id": 878404792
}
EOF
```

## CheckRepository

```sh
curl -0 -v -X POST \
https://osslicensecompliance-twirp-staging.service.iad.github.net/twirp/oss_license_compliance.v0.LicenseCompliance/CheckRepository \
-H "Content-Type: application/json" \
-o result.json \
--data-binary @- << EOF
{
    "organization_id": 9919,
    "repository_id": 878404792
}
EOF
```

# Production curls

Prepare the HMAC header of the requests:

* Get one of the HMAC keys from the vault:

```sh
ssh <username>@vault-bastion.githubapp.com
. vault-login 
vault-secret --application osslicensecompliance --environment production --key TWIRP_HMAC_KEYS
```

* Compute the HMAC header from the HMAC_KEY:

```sh
TIMESTAMP=$(date +%s)
HMAC_SIGNATURE=$(echo -n "$TIMESTAMP" | openssl dgst -sha256 -hmac "$HMAC_KEY")
```

## GetAlert

```sh
curl -0 -v POST \
https://osslicensecompliance-twirp-production.service.iad.github.net/twirp/oss_license_compliance.v0.LicenseCompliance/GetAlert \
-H "Content-Type: application/json" \
-H "Request-HMAC: ${TIMESTAMP}.${HMAC_SIGNATURE}" \
--data-binary @- << EOF
{
    "repository_id": "1033407683",
    "number": "1"
}
EOF
```
