
require_relative "./abstract_manifest"
require_relative "./abstract_dependency"
require_relative "./dependency_vulnerabilities_hash"

# We currently have three versions of manifest / dependency we support (maybe 4 w/DR)
# It's not ideal that we have so many "source" model types floating around, but the
# object model that ./manifest and ./dependency provide adapts each fo them into a common schema.

#   DS-API are the proto contracts we get from dependency-snapshots-api.
require_relative "./ds_api_dependency"
require_relative "./ds_api_manifest"
#   DB Manifests are manifests we've stored in our database, usually after a parsing operation.
require_relative "./db_manifest"
require_relative "./db_dependency"
#   Parsed Manifests are manifests we've parsed, but not committed.
require_relative "./parsed_manifest"
require_relative "./parsed_manifest_dependency"
