# Staging Curls
- [Staging Curls](#staging-curls)
  - [CreateOrganizationPolicy](#createorganizationpolicy)
  - [GetOrganizationPolicy](#getorganizationpolicy)
  - [CreateEnterprisePolicy](#createenterprisepolicy)
  - [GetEnterprisePolicy](#getenterprisepolicy)
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
https://osslicensecompliance-twirp-staging.service.iad.github.net/twirp/github.osscompliance_service.LicenseCompliance/CreateOrganizationPolicy \
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
            "match_licenses": ["MIT"],
            "expires":"2025-12-09T15:44:31.894Z"
        }
        ],
        "curations": [
        {
            "package_manager": "PACKAGE_MANAGER_NPM",
            "package_name": "lodash",
            "reason": "curation-reason",
            "match_licenses": ["MIT"],
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
https://osslicensecompliance-twirp-staging.service.iad.github.net/twirp/github.osscompliance_service.LicenseCompliance/GetOrganizationPolicy \
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
https://osslicensecompliance-twirp-staging.service.iad.github.net/twirp/github.osscompliance_service.LicenseCompliance/CreateEnterprisePolicy \
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
            "match_licenses": ["MIT"],
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
https://osslicensecompliance-twirp-staging.service.iad.github.net/twirp/github.osscompliance_service.LicenseCompliance/GetEnterprisePolicy \
-H "Content-Type: application/json" \
--data-binary @- << EOF
{
    "enterprise_id": 200
}
EOF
```

## CreateRepositoryPolicy

```sh
curl -0 -v -X POST \
https://osslicensecompliance-twirp-staging.service.iad.github.net/twirp/github.osscompliance_service.LicenseCompliance/CreateRepositoryPolicy \
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
https://osslicensecompliance-twirp-staging.service.iad.github.net/twirp/github.osscompliance_service.LicenseCompliance/GetRepositoryPolicy \
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
https://osslicensecompliance-twirp-staging.service.iad.github.net/twirp/github.osscompliance_service.LicenseCompliance/CheckRepository \
-H "Content-Type: application/json" \
-o result.json \
--data-binary @- << EOF
{
    "organization_id": 9919,
    "repository_id": 878404792
}
EOF
```