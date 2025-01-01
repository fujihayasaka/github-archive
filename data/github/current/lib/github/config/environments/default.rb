# typed: true
# frozen_string_literal: true

# Default environment config. This file is required by all of the other
# environment configs and is useful for setting up global defaults. This
# is sourced in the enterprise.rb environment file too, so please make
# sure you take that into account when you update this file.
elasticsearch_port = if explicit_port_choice = ENV["GH_ELASTICSEARCH_PORT"]
  explicit_port_choice # Always prefer an explicit choice of port.
else
  9400 # Use the port that ES 8 runs on by convention.
end

GitHub.elasticsearch_host = "#{ENV.fetch('GH_ELASTICSEARCH_HOST', 'localhost')}:#{elasticsearch_port}"
GitHub.signup_enabled = true
GitHub.realtime_backups_enabled = false
GitHub.profiling_enabled = true
GitHub.stats_ui_enabled = true
GitHub.request_limiting_enabled = false

# Statsd
GitHub.stats_hosts = ["127.0.0.1:8127"]

GitHub.enterprise_web_url = ENV["ENTERPRISE_WEB_URL"]
GitHub.enterprise_web_url ||= if GitHub::AppEnvironment.production?
  "https://enterprise.github.com"
else
  "https://enterprise.github.localhost"
end

GitHub.enterprise_web_admin_url = ENV["ENTERPRISE_WEB_ADMIN_URL"]
GitHub.enterprise_web_admin_url ||= if GitHub::AppEnvironment.production?
  "https://enterprise-admin.githubapp.com"
else
  "https://enterprise.github.localhost"
end

GitHub.enterprise_web_hmac = ENV["ENTERPRISE_WEB_HMAC"]
GitHub.enterprise_web_hmac ||= "d9de584042bab368ba1ccd654fad95c5" if GitHub::AppEnvironment.development? || GitHub::AppEnvironment.test?

GitHub.treelights_url = GitHub.environment.fetch("TREELIGHTS_ENDPOINT", "http://treelights.localhost:8002")

GitHub.aleph_url = GitHub.environment.fetch("ALEPH_URL", "http://aleph.localhost:8003")
GitHub.aleph_slow_url = GitHub.environment.fetch("ALEPH_SLOW_URL", "http://aleph.localhost:8007")
GitHub.aleph_api_hmac_key = ENV["ALEPH_API_HMAC_KEY"]

GitHub.aqueduct_primary_url = GitHub.environment.fetch("AQUEDUCT_PRIMARY_URL", "http://localhost:18081/twirp")
# Use a single aqueduct cluster in dev
GitHub.aqueduct_gateway_url = GitHub.aqueduct_primary_url
GitHub.aqueduct_secondary_url = GitHub.aqueduct_primary_url
# Optionally use a specific Aqueduct URL for Hookshot
GitHub.aqueduct_hookshot_url = GitHub.environment.fetch("AQUEDUCT_HOOKSHOT_URL", GitHub.aqueduct_gateway_url)
GitHub.aqueduct_hookshot_staging_url = GitHub.environment.fetch("AQUEDUCT_HOOKSHOT_STAGING_URL", GitHub.aqueduct_gateway_url)
GitHub.aqueduct_notifyd_url = GitHub.aqueduct_gateway_url
GitHub.aqueduct_staging_url = GitHub.environment.fetch("AQUEDUCT_STAGING_URL", "http://localhost:18081/twirp")

GitHub.flippers_should_clear_actor_cache = false

GitHub.blackbird_use_fake_data = false
GitHub.blackbird_use_fake_legacy_data = false
GitHub.blackbird_url = GitHub.environment.fetch("BLACKBIRD_MW_URL", "https://blackbird-query-production.service.iad.github.net/twirp")
GitHub.blackbird_lab_url = "https://blackbird-query-lab.service.iad.github.net/twirp"
GitHub.blackbird_hmac_key = GitHub.environment.fetch("BLACKBIRD_FE_BLACKBIRD_QUERY_HMAC_KEY", "")

GitHub.blackbird_disable_analysis = false
GitHub.blackbird_mw_analysis_url = GitHub.environment.fetch("BLACKBIRD_MW_ANALYSIS_URL", "https://blackbird-mw-analysis-production.service.iad.github.net/twirp")
GitHub.blackbird_mw_analysis_lab_url = "https://blackbird-mw-analysis-lab.service.iad.github.net/twirp"
GitHub.blackbird_mw_analysis_hmac_key = GitHub.environment.fetch("BLACKBIRD_MW_ANALYSIS_HMAC_KEY", "")

# TODO: These services are not 100% wired up yet (Rust-based query services).
GitHub.blackbird_lexical_search_url = GitHub.environment.fetch("BLACKBIRD_LEXICAL_SEARCH_URL", "https://blackbird-mw-lexical-production.service.iad.github.net/twirp")
GitHub.blackbird_lexical_search_lab_url = "https://blackbird-mw-lexical-lab.service.iad.github.net/twirp"
GitHub.blackbird_lexical_search_hmac_key = GitHub.environment.fetch("BLACKBIRD_MW_LEXICAL_HMAC_KEY", "")
GitHub.blackbird_semantic_search_url = GitHub.environment.fetch("BLACKBIRD_SEMANTIC_SEARCH_URL", "https://blackbird-mw-semantic-production.service.iad.github.net/twirp")
GitHub.blackbird_semantic_search_lab_url = "https://blackbird-mw-semantic-lab.service.iad.github.net/twirp"
GitHub.blackbird_semantic_search_hmac_key = GitHub.environment.fetch("BLACKBIRD_MW_SEMANTIC_HMAC_KEY", "")

# Dependency Graph secrets
#
## DG-API
GitHub.dependency_graph_api_url = GitHub.dynamic_service_url("dependency-graph-api", 80, "/query", env: "DEPENDENCY_GRAPH_API_URL", service_name: "api", local_port: 9596)
GitHub.dependency_graph_api_hmac_key = ENV["DEPENDENCY_GRAPH_API_HMAC_KEY"].to_s
#
### DG-API Cross-Service Queues
# See: lib/dependency_graph/cross_service_job.rb
GitHub.aqueduct_dependency_graph_url = GitHub.aqueduct_gateway_url
GitHub.aqueduct_dependency_graph_send_secret = GitHub.environment["AQUEDUCT_DEPENDENCY_GRAPH_SEND_SECRET"]
GitHub.aqueduct_dependency_graph_api_key = GitHub.environment["AQUEDUCT_DEPENDENCY_GRAPH_API_KEY"]
GitHub.aqueduct_dependency_graph_api_key_version = GitHub.environment["AQUEDUCT_DEPENDENCY_GRAPH_API_KEY_VERSION"]
#
## DGP
GitHub.dependency_graph_platform_url = GitHub.dynamic_service_url("dependency-graph-platform", 80, "/", env: "DEPENDENCY_GRAPH_PLATFORM_URL", service_name: "api", local_port: 9598)
GitHub.dependency_graph_platform_hmac_keys = GitHub.environment["DEPENDENCY_GRAPH_PLATFORM_HMAC_KEYS"].to_s
#
## DS-API
GitHub.dependency_snapshots_api_url = GitHub.dynamic_service_url("dependency-snapshots-api", 80, "/twirp", env: "DEPENDENCY_SNAPSHOTS_API_URL", service_name: "api", local_port: 9597)
GitHub.dependency_snapshots_api_hmac_key = GitHub.environment["DEPENDENCY_GRAPH_API_HMAC_KEY"].to_s # NOTE: This is using DG-APIs HMAC for now
#
## OLC
GitHub.oss_license_compliance_url = GitHub.dynamic_service_url("oss-compliance", 80, "/twirp", env: "OSS_LICENSE_COMPLIANCE_URL", service_name: "api", local_port: 9599)
GitHub.oss_license_compliance_hmac_key = GitHub.environment.fetch("OSS_LICENSE_COMPLIANCE_HMAC_KEY", "oss-hmac").to_s

GitHub.diff_analysis_url = GitHub.dynamic_service_url("diff-analysis", 5020, "/twirp")

GitHub.windbeam_twirp_url = GitHub.environment.fetch("WINDBEAM_TWIRP_URL", "http://localhost:8080")
GitHub.windbeam_hmac_key = GitHub.environment.fetch("WINDBEAM_HMAC_KEY", "fiddlesticks")

GitHub.api_code_search_default_rate_limit = 10
GitHub.api_code_search_unauthenticated_rate_limit = 0
GitHub.api_code_search_enterprise_cloud_hard_rate_limit = 100

GitHub.hydro_gateway_url = GitHub.environment.fetch("HYDRO_GATEWAY_URL", "http://localhost:8085/twirp")
GitHub.hydro_aggregation_api_url = GitHub.environment.fetch("HYDRO_AGGREGATION_API_URL", "http://localhost:8085/twirp")

GitHub.turboscan_url = GitHub.dynamic_service_url("turboscan", 8888, "/twirp")

GitHub.turboscan_s3_bucket = GitHub.environment.fetch("TURBOSCAN_S3_BUCKET", "turboscan-dev")
GitHub.turboscan_azure_account_name = GitHub.environment.fetch("TURBOSCAN_AZURE_ACCOUNT_NAME", "")
GitHub.turboscan_azure_account_key = GitHub.environment.fetch("TURBOSCAN_AZURE_ACCOUNT_KEY", "")
GitHub.turboscan_azure_container = GitHub.environment.fetch("TURBOSCAN_AZURE_CONTAINER", "github-turboscan")
GitHub.turboscan_azure_storage_dns_suffix = GitHub.environment.fetch("TURBOSCAN_AZURE_STORAGE_DNS_SUFFIX", "")
GitHub.turboscan_azure_storage_tenant_id = GitHub.environment.fetch("TURBOSCAN_AZURE_STORAGE_TENANT_ID", "")
GitHub.turboscan_azure_storage_client_id = GitHub.environment.fetch("TURBOSCAN_AZURE_STORAGE_CLIENT_ID", "")
GitHub.turboscan_azure_storage_client_secret = GitHub.environment.fetch("TURBOSCAN_AZURE_STORAGE_CLIENT_SECRET", "")

GitHub.turboquality_azure_container = GitHub.environment.fetch("TURBOQUALITY_AZURE_CONTAINER", "sarif-upload")
GitHub.turboquality_azure_account_name = GitHub.environment.fetch("TURBOQUALITY_AZURE_ACCOUNT_NAME", "")
GitHub.turboquality_azure_account_key = GitHub.environment.fetch("TURBOQUALITY_AZURE_ACCOUNT_KEY", "")
GitHub.turboquality_azure_blob_host = GitHub.environment.fetch("TURBOQUALITY_AZURE_BLOB_HOST", "")

GitHub.codeql_variant_analysis_memory_alpha_bucket = GitHub.environment.fetch("CODEQL_QUERY_CONSOLE_MEMORY_ALPHA_BUCKET", "codeql-query-console")
GitHub.codeql_variant_analysis_azure_storage_account = GitHub.environment.fetch("CODEQL_QUERY_CONSOLE_AZURE_STORAGE_ACCOUNT", "queryconsoleprod")
GitHub.codeql_variant_analysis_memory_alpha_secret = GitHub.environment.fetch("CODEQL_QUERY_CONSOLE_MEMORY_ALPHA_PRIMARY_KEY", "")
GitHub.codeql_variant_analysis_azure_container = GitHub.environment.fetch("CODEQL_QUERY_CONSOLE_AZURE_CONTAINER_NAME", "")

GitHub.zendesk_api_url = ENV["ZENDESK_API_URL"]
GitHub.zendesk_api_token = ENV["ZENDESK_API_TOKEN"]

# These IDs must match what's configured in Zendesk.
# They're used to create support tickets by way of
# SiteController#send_contact.
GitHub.zendesk_brand_id = "400594"
GitHub.zendesk_fields = {
  browser:            "360016114072",
  business_plus:      "360016114092",
  category:           "360026997452",
  ip_address:         "360016163471",
  javascript_enabled: "360016114132",
  os:                 "360016163651",
  location:           "360016163691",
  login:              "360016114192",
  level:              "31396557",
  metadata:           "360016163711",
  plan:               "360016114212",
  referring_article:  "360016114232",
  referring_url:      "360016114252",
  user_spammy:        "360016114272",
  user_suspended:     "360016114292",
}

GitHub.braavos_support_entitlement_hmac = ENV["BRAAVOS_SUPPORT_ENTITLEMENT_HMAC"]
GitHub.braavos_support_entitlement_url = ENV["BRAAVOS_SUPPORT_ENTITLEMENT_URL"]

GitHub.discussion_creation_rate_limit_configuration = begin
  JSON.parse(GitHub.environment.fetch("DISCUSSION_CREATION_RATE_LIMIT_CONFIGURATION", "{}"), symbolize_names: true)
rescue JSON::ParserError
  {}
end

# In App Purchasing Support
GitHub.apple_iap_shared_secret = GitHub.environment.fetch("APPLE_IAP_SHARED_SECRET", "")
GitHub.apple_app_store_api_key_id = GitHub.environment.fetch("APPLE_APP_STORE_API_KEY_ID", "")
GitHub.apple_app_store_api_key_contents = GitHub.environment.fetch("APPLE_APP_STORE_API_KEY_CONTENTS", "")
GitHub.apple_app_store_api_issuer_id = GitHub.environment.fetch("APPLE_APP_STORE_API_KEY_ISSUER_ID", "")
GitHub.apple_skip_receipt_validation = false

GitHub.google_iap_service_account_key = GitHub.environment.fetch("GOOGLE_IAP_SERVICE_ACCOUNT_KEY", "")

# Authnd
default_authnd_port = Rails.env.test? ? "8082" : "8092"
GitHub.authnd_service_url = GitHub.environment.fetch("AUTHND_SERVICE_URL", "http://localhost:#{default_authnd_port}")
GitHub.authnd_service_mesh_url = GitHub.environment.fetch("AUTHND_SERVICE_MESH_URL", "http://localhost:#{default_authnd_port}")
GitHub.authnd_service_connection_timeout = GitHub.environment.fetch("AUTHND_SERVICE_CONNECTION_TIMEOUT", "0.1").to_f
GitHub.authnd_service_response_timeout = GitHub.environment.fetch("AUTHND_SERVICE_RESPONSE_TIMEOUT", "0.1").to_f
GitHub.authnd_issue_token_retryable = false
GitHub.authnd_mobile_request_device_auth_retryable = false
GitHub.authnd_request_max_attempts = 3
GitHub.authnd_request_wait_seconds = 0.001 # wait 1ms between request retries
GitHub.authnd_retryable_twirp_errors = [:unavailable]

# Secret Scanning
GitHub.secret_scanning_v1_api_encryption_keys_delimited = GitHub.environment.fetch("SECRET_SCANNING_V1_API_ENCRYPTION_KEYS_DELIMITED", "")
GitHub.secret_scanning_encrypted_secrets_delimited_shared_transit_keys = GitHub.environment.fetch("ENCRYPTED_SECRETS_DELIMITED_SHARED_TRANSIT_KEYS", "")
GitHub.secret_scanning_user_content_delimited_encryption_root_keys = GitHub.environment.fetch("SECRET_SCANNING_USER_CONTENT_DELIMITED_ENCRYPTION_ROOT_KEYS", "")

# Security Center
GitHub.security_center_export_azure_spn_client_secret = GitHub.environment["SPN_SECURITY_CENTER_RW_TF"]
GitHub.security_center_export_azure_spn_client_id = GitHub.environment["SPN_SECURITY_CENTER_RW_TF_CLIENT_ID"]
GitHub.security_center_export_azure_spn_tenant_id = GitHub.environment["SPN_SECURITY_CENTER_RW_TF_TENANT_ID"]
GitHub.security_center_export_azure_storage_account_name = GitHub.environment["SECURITY_CENTER_STORAGE_ACCOUNT_NAME"]
GitHub.security_center_export_azure_storage_access_key = GitHub.environment["SECURITY_CENTER_STORAGE_ACCESS_KEY"]
GitHub.security_center_export_azure_blob_container = GitHub.environment["SECURITY_CENTER_STORAGE_CONTAINER"]

# Codespaces
GitHub.codespaces_vscs_environment = GitHub::Config::VSCS_ENVIRONMENTS[:production]

GitHub.codespaces_app_key = "Iv1.ad5f73e593b03f40"
GitHub.codespaces_vm_secrets_app_key = "Iv1.267269b939642982"

# Private Registry Secrets
GitHub.private_registry_secrets_app_key = "Iv23ct5ltBS3Vk4wSHw8"

# BYOK Custom Models for GitHub Models & Copilot
GitHub.byok_custom_models_app_key = "Iv23ctQipwoLMooQHxdq"
GitHub.copilot_byok_app_key = "Iv23ctXeLyQmO2Auu7KX"
# ELM Exporter Secrets
GitHub.elm_exporter_secrets_app_key = "Iv23ctehy9m6mzmux8hy"

# Copilot
GitHub.copilot_jetbrains_language_server_auth_app_key = "Iv23ctfURkiMfJ4xr5mv"
GitHub.copilot_language_server_auth_app_key = "Ov23liV9UpD7Rnfnskm3"
GitHub.copilot_xcode_language_server_auth_app_key = "Iv23ctaj7WdQfvSpvroB"
GitHub.copilot_cli_app_key = "Ov23ctDVkRmgkPke0Mmm"

# Base64 encoded urandom string (cryptographically secure)
GitHub.codespaces_token_encryption_key = GitHub.environment.fetch("CODESPACES_TOKEN_ENCRYPTION_KEY", "")

# Limits
GitHub.codespaces_per_minute_rate_limit = 5
GitHub.codespaces_per_user_sales_demo_limit = 100
GitHub.codespaces_automated_testing_limit = Float::INFINITY

GitHub.codespaces_dockerhub_registry = {
  url: GitHub.environment.fetch("CODESPACES_REGISTRY_URL", "https://index.docker.io/v1/"),
  username: GitHub.environment.fetch("CODESPACES_REGISTRY_USERNAME", "codespacesdev"),
  password: GitHub.environment.fetch("CODESPACES_REGISTRY_PASSWORD", ""),
}

# Classroom
GitHub.classroom_api_service_url = GitHub.environment.fetch("CLASSROOM_API_SERVICE_URL", "http://localhost:5000/")
GitHub.classroom_hmac_key = GitHub.environment.fetch("CLASSROOM_HMAC_KEY", "")

# Education
GitHub.education_twirp_url = GitHub.environment.fetch("EDUCATION_TWIRP_URL", "")
GitHub.education_hmac_key = GitHub.environment.fetch("EDUCATION_HMAC_KEY", "")

# Subscription name is the stamp name in proxima
GitHub.codespaces_canonical_subscription = GitHub.environment.fetch("CODESPACES_SUBSCRIPTION", GitHub::Config::CODESPACES_CANONICAL_SUBSCRIPTION)

# The base URL of the GitHub.dev lightweight web editor that we will send users to.
GitHub.codespaces_serverless_url = "https://github.dev/"

# The URL to post credentials and partner info to when a user launches the web
# editor may be provided as a query param from the vscode auth server but must
# be one of these allowlisted values representing trusted servers.
GitHub.codespaces_serverless_allowed_auth_redirect_hosts = %w[
  github.dev
  latest.github.dev
  dev.github.dev
  latest-dev.github.dev
  ppe.github.dev
  latest-ppe.github.dev
]

# Some github.dev redirect domains are necessary for development but dangerous
# to allow for all users, so we restrict them to codespaces developers.
GitHub.codespaces_serverless_developer_restricted_auth_redirect_hosts = %w[
  dev.github.localhost
  github.localhost
  github.localhost:3000
]

# The URL to post credentials and partner info for github.dev when no host param
# is provided in the auth callback request.
GitHub.codespaces_serverless_default_auth_redirect_host = "github.dev"

# values like `eu`,`uk`,`au`,`us`,`apac`,`all`, representing the data residency boundaries Codespaces should respect
GitHub.codespaces_stamp_azure_geo = GitHub.environment.fetch("CODESPACES_AZURE_GEO", "")
# End Codespaces

GitHub.dependabot_url = GitHub.environment.fetch("DEPENDABOT_INTERNAL_URL", "")
GitHub.dependabot_hmac_key = GitHub.environment.fetch("DEPENDABOT_HMAC_KEY", "")

# Notifyd
GitHub.notifyd_production_url = GitHub.environment.fetch("NOTIFYD_PRODUCTION_URL", "")
GitHub.notifyd_hmac_key = GitHub.environment.fetch("NOTIFYD_HMAC_KEY", "")

# Package Registry Metadata
GitHub.package_registry_url = GitHub.environment.fetch("PACKAGE_REGISTRY_URL", "http://registry.github.localhost:8000")
GitHub.package_registry_metadata_hmac_key = GitHub.environment["PACKAGE_REGISTRY_METADATA_HMAC_KEY"]
GitHub.package_registry_action_packages_hmac_key = GitHub.environment["PACKAGE_REGISTRY_ACTION_PACKAGES_HMAC_KEY"]

# Container Registry
GitHub.container_registry_url = GitHub.environment.fetch("CONTAINER_REGISTRY_URL", "http://localhost:8001")
GitHub.container_registry_hmac_key = GitHub.environment["CONTAINER_REGISTRY_HMAC_KEY"]

# Trust-Metadata-API
GitHub.trust_metadata_url       = GitHub.environment.fetch("TRUST_METADATA_URL", "http://localhost:8337/twirp")
GitHub.trust_metadata_client_id = GitHub.environment.fetch("TRUST_METADATA_CLIENT_ID", "dotcom")
GitHub.trust_metadata_hmac_key  = GitHub.environment.fetch("TRUST_METADATA_HMAC_KEY", "")

# Release Attestations
# The HMAC used by Memory-Alpha to sign the asset SHA256 digest header value.
GitHub.memory_alpha_sha256_digest_hmac_key = GitHub.environment.fetch("SHA256_DIGEST_HMAC_KEY", "")
GitHub.memory_alpha_sha256_digest_secondary_hmac_key = GitHub.environment.fetch("SHA256_DIGEST_SECONDARY_HMAC_KEY", "")

# Attester Service
GitHub.attester_url = GitHub.environment.fetch("ATTESTER_URL", "http://localhost:8338/twirp")
GitHub.attester_hmac_key = GitHub.environment.fetch("ATTESTER_RELEASE_HMAC_KEY", "")

# Octoshift
GitHub.octoshift_url = GitHub.environment.fetch("OCTOSHIFT_URL", "http://localhost:3001/twirp")
GitHub.octoshift_hmac_key = GitHub.environment.fetch("OCTOSHIFT_HMAC_KEY", "octoshifthmac")

GitHub.octoshift_staging_url = GitHub.environment.fetch("OCTOSHIFT_STAGING_URL", "http://localhost:3001/twirp")
GitHub.octoshift_staging_hmac_key = GitHub.environment.fetch("OCTOSHIFT_STAGING_HMAC_KEY", "octoshifthmac")

GitHub.octoshift_review_lab_url = GitHub.environment.fetch("OCTOSHIFT_REVIEW_LAB_URL", "http://localhost:3001/twirp")
GitHub.octoshift_review_lab_hmac_key = GitHub.environment.fetch("OCTOSHIFT_REVIEW_LAB_HMAC_KEY", "octoshifthmac")

GitHub.octoshift_load_testing_url = GitHub.environment.fetch("OCTOSHIFT_LOAD_TESTING_URL", "http://localhost:3001/twirp")
GitHub.octoshift_load_testing_hmac_key = GitHub.environment.fetch("OCTOSHIFT_LOAD_TESTING_HMAC_KEY", "octoshifthmac")

GitHub.octoshift_importable_creation_rate_limit_configuration = begin
  JSON.parse(GitHub.environment.fetch("OCTOSHIFT_IMPORTABLE_CREATION_RATE_LIMIT_CONFIGURATION", "{}"), symbolize_names: true)
rescue JSON::ParserError => e
  {}
end

GitHub.octoshift_freno_max_replication_delay_ms = GitHub.environment.fetch("OCTOSHIFT_MAX_REPLICATION_DELAY_MS", "2000").to_i

GitHub.octoshift_memory_alpha_bucket = GitHub.environment.fetch("OCTOSHIFT_MEMORY_ALPHA_BUCKET", "octoshiftmigrationlogs")
GitHub.octoshift_memory_alpha_key_id = GitHub.environment.fetch("OCTOSHIFT_AZURE_STORAGE_ACCOUNT", "octoshiftstoragedev")
GitHub.octoshift_memory_alpha_access_key = GitHub.environment.fetch("OCTOSHIFT_AZURE_CONTAINER_ACCESS_KEY", "")

# OIDC certificate
GitHub.oidc_azure_ad_client_certificate_current_encoded = GitHub.environment.fetch("OIDC_AZURE_AD_CLIENT_CERTIFICATE_CURRENT_KEY", "")
GitHub.oidc_azure_ad_client_certificate_previous_encoded = GitHub.environment.fetch("OIDC_AZURE_AD_CLIENT_CERTIFICATE_PREVIOUS_KEY", "")

# GitHub Source Migrator
GitHub.git_src_migrator_url = GitHub.environment.fetch("GIT_SRC_MIGRATOR_URL", "http://localhost:4567/twirp")
GitHub.git_src_migrator_hmac_key = GitHub.environment.fetch("GIT_SRC_MIGRATOR_HMAC_KEY", "gsmhmac")

GitHub.git_src_migrator_staging_url = GitHub.environment.fetch("GIT_SRC_MIGRATOR_STAGING_URL", "http://localhost:4567/twirp")
GitHub.git_src_migrator_staging_hmac_key = GitHub.environment.fetch("GIT_SRC_MIGRATOR_STAGING_HMAC_KEY", "gsmhmac")

GitHub.git_src_migrator_review_lab_url = GitHub.environment.fetch("GIT_SRC_MIGRATOR_REVIEW_LAB_URL", "http://localhost:4567/twirp")
GitHub.git_src_migrator_review_lab_hmac_key = GitHub.environment.fetch("GIT_SRC_MIGRATOR_REVIEW_LAB_HMAC_KEY", "gsmhmac")

# GitHub-owned storage for Octoshift
GitHub.gei_archives_blob_storage_type = GitHub.environment.fetch("GEI_ARCHIVES_BLOB_STORAGE_TYPE", nil)

# GitHub-owned storage for Octoshift (Azure Blob Storage)
GitHub.gei_archives_storage_abs_container = GitHub.environment.fetch("GEI_ARCHIVES_STORAGE_ABS_CONTAINER", nil)
GitHub.gei_archives_abs_storage_account_name = GitHub.environment.fetch("GEI_ARCHIVES_ABS_STORAGE_ACCOUNT_NAME", nil)
GitHub.gei_archives_abs_spn_tenant_id = GitHub.environment.fetch("GEI_ARCHIVES_ABS_SPN_TENANT_ID", nil)
GitHub.gei_archives_abs_spn_client_id = GitHub.environment.fetch("GEI_ARCHIVES_ABS_SPN_CLIENT_ID", nil)
GitHub.gei_archives_abs_spn_client_secret = GitHub.environment.fetch("GEI_ARCHIVES_ABS_SPN_CLIENT_SECRET", nil)

# GitHub-owned storage for Octoshift (S3)
GitHub.gei_archives_aws_access_key_id = GitHub.environment.fetch("GEI_ARCHIVES_AWS_ACCESS_KEY_ID", nil)
GitHub.gei_archives_aws_secret_access_key = GitHub.environment.fetch("GEI_ARCHIVES_AWS_SECRET_ACCESS_KEY", nil)

# GH Migrator
GitHub.gh_migrator_batch_size = GitHub.environment.fetch("GH_MIGRATOR_BATCH_SIZE", "").to_i

# Copilot
GitHub.copilot_api_override_url = GitHub.environment.fetch("COPILOT_API_OVERRIDE_URL", nil)

# Token scanning service
GitHub.token_scanning_url = GitHub.environment.fetch("TOKEN_SCANNING_URL", "http://localhost:5000/twirp")
GitHub.token_scanning_scans_api_url = GitHub.environment.fetch("TOKEN_SCANNING_SCANS_API_URL", "http://localhost:5000/twirp")
GitHub.token_scanning_staging_url = GitHub.environment.fetch("TOKEN_SCANNING_STAGING_URL", "http://localhost:5000/twirp")

# Pages service-to-service authentication
# pages deployer
GitHub.pages_deployer_url = GitHub.environment.fetch("PAGES_DEPLOYER_API_HTTP_ADDR", "http://localhost:9090/twirp")
GitHub.pages_deployer_hmac_key = GitHub.environment.fetch("PAGES_DEPLOYER_API_HMAC_SECRET", "test")

# Pages build server service-to-service authentication
# todo: do we need to duplicate this without ENTERPRISE_ ?
GitHub.pages_builds_hmac_key = GitHub.environment.fetch(
  "ENTERPRISE_PAGES_BUILDS_HMAC_KEY", ""
)

GitHub.gitbackupsd_url = GitHub.environment.fetch("GITBACKUPSD_URL", "http://localhost:8082/twirp/")

# Overrides the default OpenTelemetry collector endpoint to send traces to and allows a controlled rollout per app-role using region specific environment variables.
#
# E.g. to deploy to unicorn and api roles in va3-iad set these variables in vault:
# VA3_IAD_OTEL_ROLES=unicorn,api
# VA3_IAD_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=https://otel-collector.example.com:4317
# VA3_IAD_OTEL_EXPORTER_OTLP_TRACES_HEADERS="Authorization=Basic:%20<base64 encoded auth token>"
#
# See { GitHub::Config::PrefixEnvironment } for more details.
if Array(GitHub.environment.fetch("OTEL_ROLES", "").split(",")).include?(GitHub.role.to_s) && GitHub.environment["OTEL_EXPORTER_OTLP_TRACES_ENDPOINT"].present?
  ENV["OTEL_EXPORTER_OTLP_TRACES_ENDPOINT"] = GitHub.environment.fetch("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT")
  ENV["OTEL_EXPORTER_OTLP_TRACES_HEADERS"] = GitHub.environment.fetch("OTEL_EXPORTER_OTLP_TRACES_HEADERS")
end

# Overrides the default endpoints to send telemetry via the service mesh.
#
# E.g. to deploy to unicorn and api roles in va3-iad set these variables in vault:
# VA3_IAD_SERVICE_MESH_ENABLED=true
# VA3_IAD_OTEL_MESH_ENVS=production/canary,review-lab
#
# See { GitHub::Config::PrefixEnvironment } for more details.
if GitHub.environment.fetch("SERVICE_MESH_ENABLED", "false") == "true"
  ENV["OTEL_EXPORTER_OTLP_TRACES_ENDPOINT"] = ENV["OTEL_EXPORTER_OTLP_TRACES_ENDPOINT_MESH"]
  ENV["FAILBOT_HAYSTACK_URL"] = ENV["FAILBOT_HAYSTACK_URL_MESH"]
end

GitHub.issues_graph_api_url = GitHub.environment.fetch("ISSUES_GRAPH_API_URL", "http://localhost:8989/twirp") unless ENV["GITHUB_CONFIG_SKIP_ISSUES_GRAPH"]

ENV["FAILBOT_RAISE_PROCESSING_ERRORS"] ||= "false"
GitHub.missing_user_notice_behavior = :failbot

# OTel Semantic Conventions for Logging
GitHub.semconv_enabled = GitHub.environment.fetch("SEMCONV_ENABLED", "false") == "true"
GitHub.otel_logger_enabled = GitHub.environment.fetch("OTEL_LOGGER_ENABLED", "false") == "true"

ENV["OTEL_SERVICE_NAME"] ||= ["github", ENV["GITHUB_CONFIG_ROLE"]].compact.join("-")

# GitHub processes may not play well with the default asychronous log appender, so we are forcing logs to be streamed synchronously
ENV["GITHUB_TELEMETRY_LOGS_ENABLE_SYNC_APPENDER"] = "true"

# GH Supported API Versions
GitHub.api_versions = %w[
  2022-11-28
]

# Initialize propagation information for Feature Management
GitHub.set_feature_management_current_stamp
GitHub.set_feature_management_feature_flag_hub_hmac_key
GitHub.set_feature_management_feature_flag_hub_mgmt_hmac_key
GitHub.set_feature_management_feature_flag_hub_checks_hmac_key
GitHub.set_feature_management_feature_flag_hub_checks_review_lab_hmac_key
GitHub.set_feature_management_feature_flag_hub_url
GitHub.set_feature_management_feature_flag_data_url
GitHub.set_feature_management_feature_flag_data_checks_hmac_shared_key
GitHub.set_use_flipper_vexi_proxy_redirect

GitHub.gist_oauth_client_id  = ENV["GIST_OAUTH_CLIENT_ID"]
GitHub.gist_oauth_secret_key = ENV["GIST_OAUTH_SECRET_KEY"]

GitHub.porter_internal_api_token = ENV["GH_PORTER_INTERNAL_API_TOKEN"]

GitHub.hookshot_token  = ENV["HOOKSHOT_TOKEN"]
GitHub.hookshot_go_url = ENV["HOOKSHOT_GO_URL"]

GitHub.webhook_deliveries_url = ENV["WEBHOOK_DELIVERIES_URL"]
GitHub.staging_webhook_deliveries_url = ENV["WEBHOOK_DELIVERIES_STAGING_URL"]
GitHub.webhook_deliveries_token = ENV["WEBHOOK_DELIVERIES_API_TOKEN"]
GitHub.staging_webhook_deliveries_token = ENV["WEBHOOK_DELIVERIES_STAGING_API_TOKEN"]
GitHub.webhook_deliveries_path = GitHub.environment["WEBHOOK_DELIVERIES_PATH"]

# GLB-balanced low priority mail.
#
# Will attempt to send notifications via github-smtp.
# It will fallback to sendgrid in the event of a large flood of mail.
if ENV["USE_GLB_BALANCED_MAIL"]
  GitHub.smtp_port      = ENV["SMTP_PORT"]&.to_i
  GitHub.smtp_user_name = ENV["GLB_BALANCED_MAIL_SMTP_USER"]
  GitHub.smtp_password  = ENV["GLB_BALANCED_MAIL_SMTP_PASSWORD"]
end

# Used in staging labs, which send all emails via SendGrid.
if ENV["GITHUB_USE_SENDGRID"]
  GitHub.smtp_port      = ENV["GITHUB_SMTP_PORT"]
  GitHub.smtp_user_name = ENV["GITHUB_SMTP_USER"]
  GitHub.smtp_password  = ENV["GITHUB_SMTP_PASSWORD"]
end

GitHub.session_secret            = ENV["SESSION_SECRET"]
GitHub.image_proxy_key           = ENV["IMAGE_PROXY_KEY"]

# Alive config variables
GitHub.alive_encryption_key      = ENV["ALIVE_ENCRYPTION_KEY"]
GitHub.longpoll_socket_id_secret = ENV["LONGPOLL_SOCKET_ID_SECRET"]

# Alive staging config variables
GitHub.alive_staging_socket_id_secret = ENV["ALIVE_STAGING_SOCKET_ID_SECRET"]

GitHub.octolytics_secret      = ENV["OCTOLYTICS_SECRET"]
GitHub.gist_octolytics_secret = ENV["GIST_OCTOLYTICS_SECRET"]

GitHub.hydro_browser_payload_secret = ENV["HYDRO_BROWSER_PAYLOAD_SECRET"]
GitHub.visitor_secret               = ENV["VISITOR_SECRET"]

GitHub.pond_shared_secret = ENV["POND_SHARED_SECRET"]

if GitHub.billing_enabled?
  if GitHub.proxima_billing_enabled?
    GitHub.braintree_environment = :production
    GitHub.braintree_client_token_enabled = true
    GitHub.braintree_host = GitHub.environment.fetch("BRAINTREE_HOST", "https://www.braintreegateway.com")

    GitHub.zuora_rest_server = GitHub.environment.fetch("ZUORA_REST_SERVER", "https://rest.zuora.com")
    GitHub.zuora_lfs_rate_plan_charge_ids = %w[2c92a0fe5bb40fd8015bd9f0ca750eec 2c92a0076adb6fd4016ae80922c47bac 2c92a0086d8c713a016db25cb2341be6]

    # 8a12924d8847b67f01884a4a1eec2c9a = GitHub Premium Support Standard (EMU)
    # 2c92a0fe662069630166548634a72782 = GitHub Premium Support Standard
    # 2c92a0fe5ea2f1df015ebf263c8f66d2 = GitHub Premium Support Annual
    GitHub.zuora_github_premium_support_charge_ids = %w[8a12924d8847b67f01884a4a1eec2c9a 2c92a0fe662069630166548634a72782 2c92a0fe5ea2f1df015ebf263c8f66d2]

    # 8a12989f8847b68c01884a46a95a4c93 = GitHub Premium Support Plus (EMU)
    # 8a12800988479cf2018849a3480975b5 = GitHub Engineering Direct (PSP) (EMU)
    # 2c92a0fc66c9609d0166ccef1fc26aa2 = GitHub Premium Support Plus Annual
    GitHub.zuora_github_premium_support_plus_charge_ids = %w[8a12989f8847b68c01884a46a95a4c93 8a12800988479cf2018849a3480975b5 2c92a0fc66c9609d0166ccef1fc26aa2]

    # 2c92a00d74bf31780174c652071d3ce0 = GitHub Premium Support Plus Annual - MSFT
    GitHub.zuora_github_premium_support_plus_msft_charge_ids = ["2c92a00d74bf31780174c652071d3ce0"]

    # 2c92a0086a2ea9d5016a32bf801171eb = GitHub Enterprise Campus Program - Free Annual
    GitHub.zuora_github_enterprise_campus_program_charge_ids = ["2c92a0086a2ea9d5016a32bf801171eb"]

    GitHub.zuora_metered_refill_rate_plan_charge_ids = %w[2c92a0fe6e880084016e8f69fcc35147 8a1290f186ea14aa01870a6238307f44]

    GitHub.zuora_sales_serve_actions_product_charge_ids = ["2c92a0fe6fcbd8d4016fd4d8cd831ff7"]
    GitHub.zuora_sales_serve_packages_product_charge_ids = ["2c92a00e6fcbd837016fd4f7a5a50c8b"]
    GitHub.zuora_sales_serve_shared_storage_product_charge_ids = ["2c92a0076fcbd887016fd4e331be567e"]

    GitHub.zuora_sales_serve_ghe_ghas_mapping = {
      "2c92a0fe6d8c63f6016db26c619a11cc" => "2c92a00d6d4dcd59016d609dd91b746e",
    }
    GitHub.zuora_sales_serve_ghe_product_charge_ids = GitHub.zuora_sales_serve_ghe_ghas_mapping.keys
    GitHub.zuora_sales_serve_ghas_product_charge_ids = GitHub.zuora_sales_serve_ghe_ghas_mapping.values.uniq
    GitHub.zuora_sales_serve_secret_protection_charge_ids = %w[dbbe01963feb9ccb3ce1ea6bf4bf0000 dbbe01963f8d7c2225ca75ccebfe0001 dbbe01964091e486c87c8a0d693c0001] # cloud, server, unified
    GitHub.zuora_sales_serve_code_security_charge_ids = %w[dbbe01963fa56e4dc760786990ab0000 dbbe01963f79c8f84658b9cd352f0001 dbbe0196401eda367be5f80b52690001] # cloud, server, unified

    GitHub.zuora_sales_serve_msft_ghas_product_charge_ids = %w[2c92a00f72929f210172964b0bcb52fc 2c92a00f72929f210172964b0c57530c 2c92a00f72929f210172964b0c135304 2c92a00f72929f210172964b0b7a52f4]
    GitHub.zuora_sales_serve_other_ghas_charge_ids = %w[8a129b298bdd5e1e018bee8a8fc93253 2c92a0ff7bde4302017be60812db58a5] # startup program, partner demo
    GitHub.zuora_sales_serve_msft_secret_protection_charge_ids = %w[dbbe019568eefb59fac7bbae04470007 dbbe019568eefb59fac7bbae054b0013 dbbe019568eefb59fac7bbae04c6000d dbbe019568eefb59fac7bbae03c70001]
    GitHub.zuora_sales_serve_msft_code_security_charge_ids = %w[dbbe019568048d4fcede02abde020007 dbbe019568048d4fcede02abdf100013 dbbe019568048d4fcede02abde86000d dbbe019568048d4fcede02abdd790001]

    GitHub.zuora_sales_serve_codespaces_product_charge_ids = { compute: "2c92a0fe74356be001744d55760d11ee", storage: "2c92a0fe74356be001744d55764c11f8" }

    GitHub.zuora_payment_page_server = GitHub.environment.fetch("ZUORA_PAYMENT_PAGE_SERVER", "https://www.zuora.com/")
    GitHub.zuora_payment_page_uri = GitHub.environment.fetch("ZUORA_PAYMENT_PAGE_URI", "https://www.zuora.com/apps/PublicHostedPageLite.do")
    GitHub.zuora_host = GitHub.environment.fetch("ZUORA_HOST", "https://www.zuora.com")
    # The Zuora id for the "Other" system payment method (used for payments unrelated to a specific payment instrument)
    GitHub.zuora_other_payment_method_id = GitHub.environment.fetch("ZUORA_OTHER_PAYMENT_METHOD_ID", "2c92a0fc57fb750d015802ab95f70e27")

    GitHub.zuora_invoices_light_default_payment_page_id = GitHub.environment.fetch("ZUORA_INVOICES_LIGHT_DEFAULT_PAYMENT_PAGE_ID", "8a12904196f703350196f9941da452df")
    GitHub.zuora_settings_compact_auto_default_payment_page_id = GitHub.environment.fetch("ZUORA_SETTINGS_COMPACT_AUTO_DEFAULT_PAYMENT_PAGE_ID", "8a1280be9521b41001953a29ae00324e")
    GitHub.zuora_settings_compact_dark_default_payment_page_id = GitHub.environment.fetch("ZUORA_SETTINGS_COMPACT_DARK_DEFAULT_PAYMENT_PAGE_ID", "8a12826b9744d7a101976a15560a0101")
    GitHub.zuora_settings_compact_light_default_payment_page_id = GitHub.environment.fetch("ZUORA_SETTINGS_COMPACT_LIGHT_DEFAULT_PAYMENT_PAGE_ID", "8a128eb49744d7ab019769e46c3e3180")
    GitHub.zuora_settings_regular_auto_default_payment_page_id = GitHub.environment.fetch("ZUORA_SETTINGS_REGULAR_AUTO_DEFAULT_PAYMENT_PAGE_ID", "8a1297979744f21f01976a06d22553a1")
    GitHub.zuora_settings_regular_dark_default_payment_page_id = GitHub.environment.fetch("ZUORA_SETTINGS_REGULAR_DARK_DEFAULT_PAYMENT_PAGE_ID", "8a12826b9744d7a101976a0d7eb76f42")
    GitHub.zuora_settings_regular_light_default_payment_page_id = GitHub.environment.fetch("ZUORA_SETTINGS_REGULAR_LIGHT_DEFAULT_PAYMENT_PAGE_ID", "8a1290419521cd0301953a0786e810b0")
    GitHub.zuora_sign_up_light_default_payment_page_id = GitHub.environment.fetch("ZUORA_SIGN_UP_LIGHT_DEFAULT_PAYMENT_PAGE_ID", "8a1281759744d79e0197660aafcc52bd")
  end

  GitHub.braintree_merchant_id                = ENV["GH_BRAINTREE_MERCHANT_ID"]
  GitHub.braintree_public_key                 = ENV["GH_BRAINTREE_PUBLIC_KEY"]
  GitHub.braintree_private_key                = ENV["GH_BRAINTREE_PRIVATE_KEY"]

  GitHub.taxamo_api_host                           = ENV.fetch("TAXAMO_API_HOST", "https://services.taxamo.com")
  GitHub.taxamo_api_private_token                  = ENV["TAXAMO_API_PRIVATE_TOKEN"]

  GitHub.zuora_access_key_id                       = ENV["ZUORA_ACCESS_KEY_ID"]
  GitHub.zuora_secret_access_key                   = ENV["ZUORA_SECRET_ACCESS_KEY"]
  GitHub.zuora_client_id                           = ENV["ZUORA_CLIENT_ID"]
  GitHub.zuora_client_secret                       = ENV["ZUORA_CLIENT_SECRET"]
  GitHub.zuora_apm_rest_server                     = GitHub.environment.fetch("ZUORA_APM_REST_SERVER", "https://advanced-payment-manager.apps.zuora.com")
  GitHub.zuora_apm_username                        = ENV["ZUORA_APM_USERNAME"]
  GitHub.zuora_apm_api_token                       = ENV["ZUORA_APM_API_TOKEN"]
  GitHub.zuora_webhook_username                    = ENV["ZUORA_WEBHOOK_USERNAME"]
  GitHub.zuora_webhook_password                    = ENV["ZUORA_WEBHOOK_PASSWORD"]
  GitHub.zuora_webhook_new_password                = ENV["ZUORA_WEBHOOK_NEW_PASSWORD"]
  GitHub.zuora_sponsors_payment_gateway_id         = ENV["ZUORA_SPONSORS_PAYMENT_GATEWAY_ID"]
  GitHub.zuora_self_serve_communication_profile_id = ENV["ZUORA_SELF_SERVE_COMMUNICATION_PROFILE_ID"]

  GitHub.stripe_platform_webhook_secret = ENV["STRIPE_PLATFORM_WEBHOOK_SECRET"]
  GitHub.stripe_connect_webhook_secret  = ENV["STRIPE_CONNECT_WEBHOOK_SECRET"]
  GitHub.stripe_api_key                 = ENV["STRIPE_API_KEY"]
  GitHub.stripe_client_id               = ENV["STRIPE_CLIENT_ID"]
  # The Stripe API key for the "Stripe v3" payment gateway configured in Zuora
  GitHub.stripe_v3_api_key              = ENV["STRIPE_V3_API_KEY"]
  # The Stripe webhook secret for the "Stripe v3" payment gateway configured in Zuora
  GitHub.stripe_v3_platform_webhook_secret = ENV["STRIPE_V3_PLATFORM_WEBHOOK_SECRET"]
end

if GitHub.sponsors_enabled?
  GitHub.patreon_client_id      = ENV["PATREON_CLIENT_ID"]
  GitHub.patreon_client_secret  = ENV["PATREON_CLIENT_SECRET"]
end

GitHub.vss_subscription_events_topic_name        = ENV["VSS_SUBSCRIPTION_EVENTS_TOPIC_NAME"]
GitHub.vss_subscription_events_subscription_name = ENV["VSS_SUBSCRIPTION_EVENTS_SUBSCRIPTION_NAME"]
GitHub.vss_subscription_events_connection_string = ENV["VSS_SUBSCRIPTION_EVENTS_CONNECTION_STRING"]
GitHub.vss_status_messages_queue_name            = ENV["VSS_STATUS_MESSAGES_QUEUE_NAME"]
GitHub.vss_status_messages_connection_string     = ENV["VSS_STATUS_MESSAGES_CONNECTION_STRING"]

GitHub.webhook_forwarder_url = GitHub.environment.fetch("WEBHOOK_FORWARDER_URL", "wss://webhook-forwarder.github.com")

GitHub.open_exchange_rates_app_id = ENV["GH_OPEN_EXCHANGE_RATES_APP_ID"]

GitHub.alambic_cdn_token         = ENV["ALAMBIC_CDN_TOKEN"]
GitHub.s3_alambic_access_key     = ENV["S3_ALAMBIC_ACCESS_KEY"]
GitHub.s3_alambic_secret_key     = ENV["S3_ALAMBIC_SECRET_KEY"]
GitHub.alambic_replication_token = ENV["ALAMBIC_REPLICATION_TOKEN"]

if GitHub.multi_tenant_enterprise?
  GitHub.alambic_avatars_hmac_key = ENV["AVATARS_HMAC_KEY"]
end

# % chance that the 2nd avatar and/or browser avatar version is used
GitHub.alambic_next_avatar_chance = ENV["ALAMBIC_NEXT_AVATAR_CHANCE"]

GitHub.es_auto_expand_replicas = GitHub.environment.fetch_boolean("ES_AUTO_EXPAND_REPLICAS", false)
GitHub.es_number_of_replicas = GitHub.environment.fetch("ES_NUMBER_OF_REPLICAS", GitHub::Config::ES_NUMBER_OF_REPLICAS).to_i

GitHub.launch_deployer_twirp_address     = GitHub.dynamic_service_url("launch", 80, "", env: "LAUNCH_DEPLOYER_TWIRP_URL", service_name: "launch-deployer", local_port: 5001)
GitHub.launch_deployer_hmac_secret       = GitHub.environment["LAUNCH_DEPLOYER_HMAC_SECRET"]
GitHub.launch_lab_deployer_twirp_address = GitHub.environment["LAUNCH_LAB_DEPLOYER_TWIRP_URL"]
GitHub.launch_lab_deployer_hmac_secret   = GitHub.environment["LAUNCH_LAB_DEPLOYER_HMAC_SECRET"]
GitHub.launch_grpc_ca_certificates_path  = GitHub.environment.fetch("LAUNCH_GRPC_CA_CERTIFICATES_PATH", "/etc/ssl/certs/ca-certificates.crt")

if GitHub.dynamic_lab?
  GitHub.kredz_address     = GitHub.environment.fetch("KREDZ_LAB_URL", "")
  GitHub.kredz_hmac_secret = GitHub.environment.fetch("KREDZ_LAB_CREDZ_HMAC_SECRET", "")

  GitHub.varz_address      = GitHub.environment.fetch("VARZ_LAB_URL", "")
  GitHub.varz_hmac_secret  = GitHub.environment.fetch("VARZ_LAB_HMAC_SECRET", "")
else
  GitHub.kredz_address     = GitHub.environment.fetch("KREDZ_URL", "")
  GitHub.kredz_hmac_secret = GitHub.environment.fetch("KREDZ_PRODUCTION_HMAC_SECRET", "")

  GitHub.varz_address      = GitHub.environment.fetch("VARZ_URL", "")
  GitHub.varz_hmac_secret  = GitHub.environment.fetch("VARZ_HMAC_SECRET", "")
end

# social login oidc client values
GitHub.google_social_client_id = GitHub.environment.fetch("SOCIAL_GOOGLE_CLIENT_ID", "your-test-client-id")
GitHub.google_social_client_secret = GitHub.environment.fetch("SOCIAL_GOOGLE_CLIENT_SECRET", "your-test-client-secret")

GitHub.apple_social_client_id = GitHub.environment.fetch("SOCIAL_APPLE_CLIENT_ID", "your-test-apple-client-id")
GitHub.apple_social_private_key = GitHub.environment.fetch("SOCIAL_APPLE_PRIVATE_KEY", "your-test-apple-private-key")
GitHub.apple_social_team_id = GitHub.environment.fetch("SOCIAL_APPLE_TEAM_ID", "your-test-apple-team-id")
GitHub.apple_social_key_id = GitHub.environment.fetch("SOCIAL_APPLE_KEY_ID", "your-test-apple-key-id")

# Set keys for two-factor secrets encryption
GitHub.recovery_code_salt_version = GitHub.environment.fetch("RECOVERY_CODE_SALT_VERSION", 1)
GitHub.recovery_code_salts = begin
  JSON.parse(GitHub.environment.fetch("RECOVERY_CODE_SALTS", "{}"))
rescue JSON::ParserError
  {}
end
GitHub.sms_otp_salts = GitHub.environment["SMS_OTP_SALTS"].to_s.split(",")
GitHub.app_otp_salt_version = GitHub.environment.fetch("APP_OTP_SALT_VERSION", 1)
GitHub.app_otp_salts = begin
  JSON.parse(GitHub.environment.fetch("APP_OTP_SALTS", "{}"))
rescue JSON::ParserError
  {}
end


# Set key for SAML provider secrets encryption
GitHub.saml_provider_salt = ENV["SAML_PROVIDER_SALT"]

# Twilio API credentials
GitHub.twilio_sid   = ENV["TWILIO_SID"]
GitHub.twilio_token = ENV["TWILIO_TOKEN"]
GitHub.twilio_callback_url = ENV["TWILIO_CALLBACK_URL"]

# Nexmo API credentials
GitHub.nexmo_api_key    = ENV["NEXMO_API_KEY"]
GitHub.nexmo_api_secret = ENV["NEXMO_API_SECRET"]
GitHub.nexmo_callback_url = ENV["NEXMO_CALLBACK_URL"]

# Vonage API credentials
GitHub.vonage_application_id = ENV["VONAGE_APPLICATION_ID"]
GitHub.vonage_private_key = ENV["VONAGE_PRIVATE_KEY"]
GitHub.vonage_messages_callback_url = ENV["VONAGE_MESSAGES_CALLBACK_URL"]

GitHub.password_lowercase_requirement         = ENV["PASSWORD_LOWERCASE_REQUIREMENT"]
GitHub.password_uppercase_requirement         = ENV["PASSWORD_UPPERCASE_REQUIREMENT"]
GitHub.password_digit_requirement             = ENV["PASSWORD_DIGIT_REQUIREMENT"]
GitHub.password_special_character_requirement = ENV["PASSWORD_SPECIAL_CHARACTER_REQUIREMENT"]

GitHub.fastly_api_token = ENV["FASTLY_API_TOKEN"]

GitHub.voltron_secret = ENV["VOLTRON_HMAC"]

# Contentful
GitHub.contentful_readme_delivery_token    = ENV["CONTENTFUL_README_DELIVERY_TOKEN"]
GitHub.contentful_marketing_delivery_token = ENV["CONTENTFUL_MARKETING_DELIVERY_TOKEN"]
GitHub.contentful_customer_stories_delivery_token = ENV["CONTENTFUL_CUSTOMER_STORIES_DELIVERY_TOKEN"]
GitHub.contentful_marketing_preview_token = ENV["CONTENTFUL_MARKETING_PREVIEW_TOKEN"]
GitHub.contentful_preview_api_host = GitHub.environment.fetch("CONTENTFUL_PREVIEW_API_URL", "preview.contentful.com")

GitHub.marketing_forms_api_hmac_key = ENV["MARKETING_FORMS_API_HMAC_KEY"]

GitHub.octocaptcha_api_hmac_secret = ENV["OCTOCAPTCHA_API_HMAC_SECRET"]
GitHub.octocaptcha_api_hmac_secret_v2 = ENV["OCTOCAPTCHA_API_HMAC_SECRET_V2"]

# Gotauth
GitHub.gotauth_address = GitHub.environment["GOTAUTH_URL"]

# Required key and url for dotcom to connection to the actions-results service
GitHub.actions_results_core_address = GitHub.dynamic_service_url("actions-results", 8080, "", env: "ACTIONS_RESULTS_CORE_URL", service_name: "results-core")
GitHub.actions_results_core_twirp_hmac_keys = GitHub.environment["ACTIONS_RESULTS_CORE_HMAC_KEYS"]

GitHub.actions_runner_admin_twirp_hmac_keys = GitHub.environment["ACTIONS_RUNNER_ADMIN_TWIRP_HMAC_KEYS"]
GitHub.actions_runner_admin_twirp_hmac_keys_lab = GitHub.environment["ACTIONS_RUNNER_ADMIN_TWIRP_HMAC_KEYS_LAB"]

GitHub.actions_broker_twirp_hmac_keys = GitHub.environment["ACTIONS_BROKER_TWIRP_HMAC_KEYS"]
GitHub.actions_broker_twirp_hmac_keys_lab = GitHub.environment["ACTIONS_BROKER_TWIRP_HMAC_KEYS_LAB"]

GitHub.actions_broker_worker_twirp_hmac_keys = GitHub.environment["ACTIONS_BROKER_WORKER_TWIRP_HMAC_KEYS"]
GitHub.actions_broker_worker_twirp_hmac_keys_lab = GitHub.environment["ACTIONS_BROKER_WORKER_TWIRP_HMAC_KEYS_LAB"]


# These are space delimited lists of keys for run service communication
GitHub.actions_run_service_twirp_hmac_keys = GitHub.environment["ACTIONS_RUN_SERVICE_HMAC_KEYS"]
GitHub.actions_run_service_lab_twirp_hmac_keys = GitHub.environment["ACTIONS_RUN_SERVICE_LAB_HMAC_KEYS"]

# Production uses the DC prefix versions of these to invoke the local gpgverify
#
# Load this before the staff env which overrides it.
GitHub.gpgverify_url = GitHub.environment["GPGVERIFY_URL"]

GitHub.munger_url = GitHub.environment["MUNGER_URL"]

GitHub.aqueduct_github_send_secret = GitHub.environment["AQUEDUCT_GITHUB_SEND_SECRET"]
GitHub.aqueduct_github_receive_secrets = GitHub.environment["AQUEDUCT_GITHUB_RECEIVE_SECRETS"].to_s.split(",")
GitHub.aqueduct_github_api_key = GitHub.environment["AQUEDUCT_GITHUB_API_KEY"]
GitHub.aqueduct_github_api_key_version = GitHub.environment["AQUEDUCT_GITHUB_API_KEY_VERSION"]

GitHub.aqueduct_staging_github_send_secret = GitHub.environment["AQUEDUCT_STAGING_GITHUB_SEND_SECRET"]
GitHub.aqueduct_staging_github_receive_secrets = GitHub.environment["AQUEDUCT_STAGING_GITHUB_RECEIVE_SECRETS"].to_s.split(",")
GitHub.aqueduct_staging_github_api_key = GitHub.environment["AQUEDUCT_STAGING_GITHUB_API_KEY"]
GitHub.aqueduct_staging_github_api_key_version = GitHub.environment["AQUEDUCT_STAGING_GITHUB_API_KEY_VERSION"]

GitHub.aqueduct_billing_platform_api_key = GitHub.environment["AQUEDUCT_BILLING_PLATFORM_API_KEY"]
GitHub.aqueduct_billing_platform_api_key_version = GitHub.environment["AQUEDUCT_BILLING_PLATFORM_API_KEY_VERSION"]

# Enqueue hookshot-go, dependency graph and notifyd jobs to production aqueduct by default, even in review-labs
GitHub.aqueduct_hookshot_api_key = GitHub.environment["AQUEDUCT_HOOKSHOT_API_KEY"]
GitHub.aqueduct_hookshot_api_key_version = GitHub.environment["AQUEDUCT_HOOKSHOT_API_KEY_VERSION"]
GitHub.aqueduct_hookshot_staging_api_key = GitHub.environment["AQUEDUCT_HOOKSHOT_STAGING_API_KEY"]
GitHub.aqueduct_hookshot_staging_api_key_version = GitHub.environment["AQUEDUCT_HOOKSHOT_STAGING_API_KEY_VERSION"]

GitHub.aqueduct_actions_api_key = GitHub.environment["AQUEDUCT_ACTIONS_PRODUCTION_API_KEY"]
GitHub.aqueduct_actions_api_key_version = GitHub.environment["AQUEDUCT_ACTIONS_PRODUCTION_API_KEY_VERSION"]

GitHub.aqueduct_chatops_api_key = GitHub.environment["AQUEDUCT_CHATOPS_PRODUCTION_API_KEY"]
GitHub.aqueduct_chatops_api_key_version = GitHub.environment["AQUEDUCT_CHATOPS_PRODUCTION_API_KEY_VERSION"]

GitHub.aqueduct_notifyd_api_key = GitHub.environment["AQUEDUCT_NOTIFYD_API_KEY"]
GitHub.aqueduct_notifyd_api_key_version = GitHub.environment["AQUEDUCT_NOTIFYD_API_KEY_VERSION"]

GitHub.aqueduct_pages_deployer_api_key = GitHub.environment["AQUEDUCT_PAGES_DEPLOYER_API_KEY"]
GitHub.aqueduct_pages_deployer_api_key_version = GitHub.environment["AQUEDUCT_PAGES_DEPLOYER_API_KEY_VERSION"]

GitHub.group_syncer_service_hmac_secret_key = GitHub.environment["TEAM_SYNC_SERVICE_HMAC_SECRET_KEY"]
GitHub.group_syncer_service_hmac_secret_primary_key = GitHub.environment["TEAM_SYNC_SERVICE_HMAC_SECRET_PRIMARY_KEY"]
GitHub.group_syncer_github_app_id = GitHub.environment["TEAM_SYNC_APP_ID"]

GitHub.qintel_api_key    = GitHub.environment["QWATCH_APIKEY"]
GitHub.qintel_api_secret = GitHub.environment["QWATCH_APISECRET"]

# Secret for the Slack integration
GitHub.slack_integration_secret = GitHub.environment["SLACK_INTEGRATION_SECRET"]

GitHub.pages_replica_count = GitHub.environment.fetch("PAGES_REPLICA_COUNT", 1).to_i

GitHub.pages_dfs_datacenters = GitHub.environment.fetch("PAGES_DFS_DATACENTERS", "azureeastus1,azureeastus2,azureeastus3").split(",")

GitHub.pages_replica_count_per_datacenters = GitHub.environment.fetch("PAGES_REPLICA_COUNT_PER_DATACENTERS", "1,1,1").split(",").map(&:to_i)

GitHub.pages_azure_replica_count = GitHub.pages_replica_count_per_datacenters.sum

# Turboquality configuration
GitHub.turboquality_url = GitHub.dynamic_service_url("turboquality", 8900, "/twirp")
GitHub.turboquality_hmac_key = GitHub.environment["TURBOQUALITY_HMAC_KEY"]

# Turboscan configuration
GitHub.turboscan_hmac_key = GitHub.environment["TURBOSCAN_HMAC_KEY"]

# TurboGHAS configuration
GitHub.turboghas_url = GitHub.dynamic_service_url("turboghas", 8866, "/twirp")
GitHub.turboghas_hmac_key = GitHub.environment["TURBOGHAS_HMAC_KEY"]
GitHub.turboghas_freno_max_replication_delay_ms = GitHub.environment.fetch("TURBOGHAS_MAX_REPLICATION_DELAY_MS", "2000").to_i

GitHub.token_scanning_hmac_key = GitHub.environment["TOKEN_SCANNING_SERVICE_HMAC_KEY"]

GitHub.authnd_service_hmac_key = GitHub.environment["AUTHND_HMAC_KEY"]
GitHub.authnd_token_exchange_secret = GitHub.environment["TOKEN_EXCHANGER_PUBLIC_KEYS"]

# Billing Platform
GitHub.billing_platform_hmac_secret_key = GitHub.environment["BILLING_PLATFORM_HMAC_KEY"]
GitHub.billing_platform_host = GitHub.environment["BILLING_PLATFORM_HOST"]

# Azure SPN for Metered Billing
GitHub.metered_billing_azure_spn_client_secret = GitHub.environment["METERED_BILLING_AZURE_SPN_CLIENT_SECRET"]
GitHub.metered_billing_azure_spn_client_id = GitHub.environment["METERED_BILLING_AZURE_SPN_CLIENT_ID"]
GitHub.metered_billing_azure_spn_tenant_id = GitHub.environment["METERED_BILLING_AZURE_SPN_TENANT_ID"]
GitHub.metered_billing_azure_storage_account_name = GitHub.environment["METERED_BILLING_STORAGE_ACCOUNT_NAME"]

# Azure SPN for Billing Account Management
GitHub.account_management_azure_spn_client_secret = GitHub.environment["ACCOUNT_MANAGEMENT_AZURE_SPN_CLIENT_SECRET"]
GitHub.account_management_azure_spn_client_id = GitHub.environment["ACCOUNT_MANAGEMENT_AZURE_SPN_CLIENT_ID"]
GitHub.account_management_azure_spn_tenant_id = GitHub.environment["ACCOUNT_MANAGEMENT_AZURE_SPN_TENANT_ID"]
GitHub.account_management_azure_storage_account_name = GitHub.environment["ACCOUNT_MANAGEMENT_STORAGE_ACCOUNT_NAME"]

# Licensing
GitHub.licensing_azure_spn_tenant_id = GitHub.environment["LICENSING_AZURE_SPN_TENANT_ID"]
GitHub.licensing_azure_spn_client_id = GitHub.environment["LICENSING_AZURE_SPN_CLIENT_ID"]
GitHub.licensing_azure_spn_client_secret = GitHub.environment["LICENSING_AZURE_SPN_CLIENT_SECRET"]
GitHub.licensing_azure_storage_account_name = GitHub.environment["LICENSING_AZURE_STORAGE_ACCOUNT_NAME"]

# Licensify
GitHub.licensify_hmac_key = GitHub.environment["LICENSIFY_HMAC_KEY"]
GitHub.licensify_host = GitHub.environment["LICENSIFY_HOST"]

# actions-usage-metrics
GitHub.actions_usage_metrics_host = GitHub.environment.fetch("ACTIONS_USAGE_METRICS_HOST", "https://actions-usage-metrics-production.service.iad.github.net")
GitHub.actions_usage_metrics_lab_hmac_key = GitHub.environment.fetch("ACTIONS_USAGE_METRICS_LAB_HMAC_KEY", "actionsusagemetricshmac")
GitHub.actions_usage_metrics_production_hmac_key = GitHub.environment.fetch("ACTIONS_USAGE_METRICS_PRODUCTION_HMAC_KEY", "actionsusagemetricshmac")

# credit decision engine
GitHub.credit_decision_engine_tenant_id = GitHub.environment.fetch("CREDIT_DECISION_ENGINE_TENANT_ID", "72f988bf-86f1-41af-91ab-2d7cd011db47")
GitHub.credit_decision_engine_client_id = GitHub.environment["CREDIT_DECISION_ENGINE_CLIENT_ID"]
GitHub.credit_decision_engine_client_secret_primary = GitHub.environment["CREDIT_DECISION_ENGINE_CLIENT_SECRET_PRIMARY"]
GitHub.credit_decision_engine_client_secret_secondary = GitHub.environment["CREDIT_DECISION_ENGINE_CLIENT_SECRET_SECONDARY"]
GitHub.credit_decision_engine_intake_api_client_id = GitHub.environment["CREDIT_DECISION_ENGINE_INTAKE_API_CLIENT_ID"]
GitHub.credit_decision_engine_intake_api_url = GitHub.environment["CREDIT_DECISION_ENGINE_INTAKE_API_URL"]
GitHub.credit_decision_engine_queue_name = GitHub.environment.fetch("CREDIT_DECISION_ENGINE_QUEUE_NAME", "github")
GitHub.credit_decision_engine_connection_string = GitHub.environment["CREDIT_DECISION_ENGINE_CONNECTION_STRING"]
GitHub.nimbus_hydro_client_cert = GitHub.environment["NIMBUS_HYDRO_CLIENT_CERT"]
GitHub.nimbus_hydro_client_key = GitHub.environment["NIMBUS_HYDRO_CLIENT_KEY"]

# trade screening
GitHub.sdn_eis_api_base_url = GitHub.environment["SDN_EIS_API_BASE_URL"]
GitHub.sdn_eis_api_sub_path = GitHub.environment["SDN_EIS_API_SUB_PATH"]
GitHub.sdn_live_api_base_url = GitHub.environment["SDN_LIVE_API_BASE_URL"]
GitHub.sdn_live_api_url_path = GitHub.environment["SDN_LIVE_API_URL_PATH"]
GitHub.ocp_apim_subscription_key = GitHub.environment["OCP_APIM_SUBSCRIPTION_KEY"]
GitHub.sdn_cohort_code = GitHub.environment["SDN_COHORT_CODE"]
GitHub.external_communication_proxy_host = GitHub.environment["EXTERNAL_COMMUNICATION_PROXY_HOST"]
GitHub.sdn_authentication_client_id = GitHub.environment["SDN_AUTHENTICATION_CLIENT_ID"]
GitHub.sdn_authentication_client_secret_primary = GitHub.environment["SDN_AUTHENTICATION_CLIENT_SECRET_PRIMARY"]
GitHub.sdn_authentication_client_secret_secondary = GitHub.environment["SDN_AUTHENTICATION_CLIENT_SECRET_SECONDARY"]
GitHub.sdn_authentication_tenant_id = GitHub.environment["SDN_AUTHENTICATION_TENANT_ID"]
GitHub.sdn_resource_eis = GitHub.environment["SDN_RESOURCE_EIS"]
GitHub.sdn_resource_live_api = GitHub.environment["SDN_RESOURCE_LIVE_API"]
GitHub.sdn_authentication_base_url = GitHub.environment["SDN_AUTHENTICATION_BASE_URL"]
GitHub.sdn_authentication_token_key = GitHub.environment["SDN_AUTHENTICATION_TOKEN_KEY"]

GitHub.encrypted_column_keying_material = GitHub.environment.fetch("ENCRYPTED_COLUMN_KEYING_MATERIAL", "")
GitHub.encrypted_column_current_encryption_key = GitHub.environment.fetch("ENCRYPTED_COLUMN_CURRENT_ENCRYPTION_KEY", "")

# Enterprise account storage
GitHub.enterprise_accounts_storage_type = GitHub.multi_tenant_enterprise? ? "azure" : GitHub.environment["ENTERPRISE_ACCOUNTS_STORAGE_TYPE"]
GitHub.enterprise_accounts_storage_azure_account_name = GitHub.environment["ENTERPRISE_ACCOUNTS_STORAGE_AZURE_ACCOUNT_NAME"]
GitHub.enterprise_accounts_storage_azure_spn_tenant_id = GitHub.environment["ENTERPRISE_ACCOUNTS_STORAGE_AZURE_SPN_TENANT_ID"]
GitHub.enterprise_accounts_storage_azure_spn_client_id = GitHub.environment["ENTERPRISE_ACCOUNTS_STORAGE_AZURE_SPN_CLIENT_ID"]
GitHub.enterprise_accounts_storage_azure_spn_client_secret = GitHub.environment["ENTERPRISE_ACCOUNTS_STORAGE_AZURE_SPN_CLIENT_SECRET"]

# Network service settings
GitHub.cps_network_service_url = GitHub.environment["CPS_NETWORK_SERVICE_URL"]
GitHub.cps_network_service_hmac_secrets = GitHub.environment["CPS_NETWORK_SERVICE_HMAC_SECRETS"]
GitHub.cps_network_url = GitHub.environment["CPS_NETWORK_URL"]

# Hosted Compute IMS settings
GitHub.hosted_compute_ims_url_curated = GitHub.environment.fetch("HOSTED_COMPUTE_IMS_URL_CURATED", "https://hosted-compute-ims-production.githubapp.com")
GitHub.hosted_compute_ims_url_customer = GitHub.environment.fetch("HOSTED_COMPUTE_IMS_URL_CUSTOMER", "https://hosted-compute-ims-#{GitHub.multi_tenant_enterprise? ? ENV["HEAVEN_DEPLOYED_ENV"] : "production"}.githubapp.com")
GitHub.hosted_compute_ims_hmac_key = GitHub.environment.fetch("HOSTED_COMPUTE_IMS_HMAC_KEY", "")

# API Insights
GitHub.api_insights_gh_azure_tenant_id = GitHub.environment.fetch("API_INSIGHTS_GH_AZURE_TENANT_ID", "")
GitHub.api_insights_sp_client_id = GitHub.environment.fetch("API_INSIGHTS_SP_CLIENT_ID", "")
GitHub.api_insights_sp_client_secret = GitHub.environment.fetch("API_INSIGHTS_SP_CLIENT_SECRET", "")
GitHub.api_insights_kusto_cluster_name = GitHub.environment.fetch("API_INSIGHTS_KUSTO_CLUSTER_NAME", "")
GitHub.api_insights_kusto_database_name = GitHub.environment.fetch("API_INSIGHTS_KUSTO_DATABASE_NAME", "hydro")
GitHub.api_insights_kusto_tabular_input_primary = GitHub.environment.fetch("API_INSIGHTS_KUSTO_TABULAR_INPUT_PRIMARY", "")
GitHub.api_insights_kusto_tabular_input_secondary = GitHub.environment.fetch("API_INSIGHTS_KUSTO_TABULAR_INPUT_SECONDARY", "")

# Copilot Metrics
GitHub.copilot_user_engagement_storage_account_name = GitHub.environment.fetch("COPILOT_USER_ENGAGEMENT_STORAGE_ACCOUNT_NAME", "")
GitHub.copilot_user_engagement_spn_tenant_id = GitHub.environment.fetch("COPILOT_USER_ENGAGEMENT_SPN_TENANT_ID", "")
GitHub.copilot_user_engagement_spn_client_id = GitHub.environment.fetch("COPILOT_USER_ENGAGEMENT_SPN_CLIENT_ID", "")
GitHub.copilot_user_engagement_spn_client_secret = GitHub.environment.fetch("COPILOT_USER_ENGAGEMENT_SPN_CLIENT_SECRET", "")
GitHub.copilot_metrics_kusto_cluster_name = GitHub.environment.fetch("COPILOT_METRICS_KUSTO_CLUSTER_NAME", "")
GitHub.copilot_direct_data_access_storage_account_name = GitHub.environment.fetch("COPILOT_DIRECT_DATA_ACCESS_STORAGE_ACCOUNT_NAME", "")
GitHub.copilot_usage_reports_spn_tenant_id = GitHub.environment.fetch("SPN_COPILOT_USAGE_REPORT_SERVER_TENANT_ID", "")
GitHub.copilot_usage_reports_spn_client_id = GitHub.environment.fetch("SPN_COPILOT_USAGE_REPORT_SERVER_CLIENT_ID", "")
GitHub.copilot_usage_reports_spn_client_secret = GitHub.environment.fetch("SPN_COPILOT_USAGE_REPORT_SERVER", "")
GitHub.copilot_usage_reports_storage_account_name = GitHub.environment.fetch("COPILOT_USAGE_REPORTS_STORAGE_ACCOUNT_NAME", "usagereports8f9e62f31b65")
GitHub.copilot_usage_reports_kusto_cluster_name = GitHub.environment.fetch("COPILOT_USAGE_REPORTS_KUSTO_CLUSTER_NAME", "metricsdevtesting.eastus")

if GitHub.multi_tenant_enterprise?
  GitHub.actions_actions_org = GitHub.environment.fetch("ACTIONS_ACTIONS_ORG", "actions")
  GitHub.actions_admin_login = GitHub.environment.fetch("ACTIONS_ADMIN_LOGIN", "actions-admin")
  GitHub.actions_enabled = GitHub.environment.fetch_boolean("ACTIONS_ENABLED", true)
  GitHub.actions_github_org = GitHub.environment.fetch("ACTIONS_GITHUB_ORG", "github")
  GitHub.actions_secrets_private_key = GitHub.environment["ACTIONS_SECRETS_PRIVATE_KEY"]
  GitHub.actions_starter_workflows_nwo = GitHub.environment.fetch("ACTIONS_STARTER_WORKFLOWS_NWO", "actions/starter-workflows")
  GitHub.actions_results_storage_accounts = GitHub.environment["ACTIONS_RESULTS_STORAGE_ACCOUNTS"]

  GitHub.alambic_avatar_url = GitHub.environment["ALAMBIC_AVATAR_URL"]
  GitHub.alambic_cdn_purge_path = GitHub.environment.fetch("ALAMBIC_CDN_PURGE_PATH", "purge")
  GitHub.alambic_cdn_url = GitHub.environment["ALAMBIC_CDN_URL"]
  GitHub.alambic_uploads_url = GitHub.environment.fetch("ALAMBIC_UPLOADS_URL", "/assets")
  GitHub.alambic_assets_url = GitHub.environment.fetch("ALAMBIC_ASSETS_URL", "/storage")
  GitHub.alloy_url = GitHub.environment["ALLOY_URL"]
  GitHub.alloy_staging_url = GitHub.environment["ALLOY_STAGING_URL"]
  GitHub.asset_host_url = GitHub.environment.fetch("ASSET_HOST_URL", "https://github.githubassets.com")
  GitHub.uploadable_storage_account = GitHub.environment["UPLOADABLE_STORAGE_ACCOUNT"]
  GitHub.uploadable_access_key = GitHub.environment["UPLOADABLE_ACCESS_KEY"]
  GitHub.lfs_storage_account = GitHub.environment["LFS_AZURE_STORAGE_ACCOUNT"]
  GitHub.lfs_access_key = GitHub.environment["LFS_AZURE_ACCESS_KEY"]
  GitHub.release_assets_storage_account = GitHub.environment["RELEASE_ASSETS_STORAGE_ACCOUNT"]

  GitHub.allow_third_party_connect_sources = GitHub.environment.fetch_boolean("ALLOW_THIRD_PARTY_CONNECT_SOURCES", false)

  #rate limits
  GitHub.api_default_rate_limit = GitHub.environment.fetch("API_DEFAULT_RATE_LIMIT", GitHub::Config::RateLimits::API_DEFAULT_RATE_LIMIT).to_i
  GitHub.api_graphql_default_rate_limit = GitHub.environment.fetch("API_GRAPHQL_DEFAULT_RATE_LIMIT", GitHub::Config::RateLimits::API_GRAPHQL_DEFAULT_RATE_LIMIT).to_i
  GitHub.api_graphql_unauthenticated_rate_limit = GitHub.environment.fetch("API_GRAPHQL_UNAUTHENTICATED_RATE_LIMIT", GitHub::Config::RateLimits::API_GRAPHQL_UNAUTHENTICATED_RATE_LIMIT).to_i
  GitHub.api_lfs_default_rate_limit = GitHub.environment.fetch("API_LFS_DEFAULT_RATE_LIMIT", GitHub::Config::RateLimits::API_LFS_DEFAULT_RATE_LIMIT).to_i
  GitHub.api_lfs_unauthenticated_rate_limit = GitHub.environment.fetch("API_LFS_UNAUTHENTICATED_RATE_LIMIT", GitHub::Config::RateLimits::API_LFS_UNAUTHENTICATED_RATE_LIMIT).to_i
  GitHub.api_search_default_rate_limit = GitHub.environment.fetch("API_SEARCH_DEFAULT_RATE_LIMIT", GitHub::Config::RateLimits::API_SEARCH_DEFAULT_RATE_LIMIT).to_i
  GitHub.api_search_unauthenticated_rate_limit = GitHub.environment.fetch("API_SEARCH_UNAUTHENTICATED_RATE_LIMIT", GitHub::Config::RateLimits::API_SEARCH_UNAUTHENTICATED_RATE_LIMIT).to_i
  GitHub.api_unauthenticated_rate_limit = GitHub.environment.fetch("API_UNAUTHENTICATED_RATE_LIMIT", GitHub::Config::RateLimits::API_UNAUTHENTICATED_RATE_LIMIT).to_i
  GitHub.api_audit_log_default_rate_limit = GitHub.environment.fetch("API_AUDIT_LOG_DEFAULT_RATE_LIMIT", GitHub::Config::RateLimits::API_AUDIT_LOG_DEFAULT_RATE_LIMIT).to_i
  GitHub.api_audit_log_unauthenticated_rate_limit = GitHub.environment.fetch("API_AUDIT_LOG_UNAUTHENTICATED_RATE_LIMIT", GitHub::Config::RateLimits::API_AUDIT_LOG_UNAUTHENTICATED_RATE_LIMIT)
  GitHub.api_audit_log_streaming_default_rate_limit = GitHub.environment.fetch("API_AUDIT_LOG_STREAMING_DEFAULT_RATE_LIMIT", GitHub::Config::RateLimits::API_AUDIT_LOG_STREAMING_DEFAULT_RATE_LIMIT).to_i
  GitHub.api_audit_log_streaming_unauthenticated_rate_limit = GitHub.environment.fetch("API_AUDIT_LOG_STREAMING_UNAUTHENTICATED_RATE_LIMIT", GitHub::Config::RateLimits::API_AUDIT_LOG_STREAMING_UNAUTHENTICATED_RATE_LIMIT)

  GitHub.asset_base_path = GitHub.environment.fetch("ASSET_BASE_PATH", "assets")
  GitHub.audit_log_es_logger_enabled = GitHub.environment.fetch_boolean("AUDIT_LOG_ES_LOGGER_ENABLED", true)
  GitHub.auth_mode = GitHub.environment["AUTH_MODE"]
  GitHub.builtin_auth_fallback = GitHub.environment["BUILTIN_AUTH_FALLBACK"]

  GitHub.cluster_git_server = GitHub.environment.fetch_boolean("CLUSTER_GIT_SERVER", false)
  GitHub.cluster_pages_server = GitHub.environment.fetch_boolean("CLUSTER_PAGES_SERVER", false)
  GitHub.cluster_web_server = GitHub.environment.fetch_boolean("CLUSTER_WEB_SERVER", false)

  GitHub.code_scanning_enabled = GitHub.environment.fetch_boolean("CODE_SCANNING_ENABLED", true)

  GitHub.desktop_fetch_interval = GitHub.environment.fetch("DESKTOP_FETCH_INTERVAL", GitHub::Config::DESKTOP_FETCH_INTERVAL).to_i
  GitHub.dgit_copies = GitHub.environment.fetch("DGIT_COPIES", GitHub::Config::DGIT_COPIES).to_i
  GitHub.dgit_git_daemon_port = GitHub.environment["DGIT_GIT_DAEMON_PORT"] # TODO: split across configuration: dev: 9418, test: 9423 + test_environment_number, prod: 9419, https://github.com/github/github/blob/9f76941bcfacb5ce1d785f501ba3d161c7d910bb/lib/github/config.rb#L1291

  # elastic search
  GitHub.es_clusters = GitHub.parse_es_clusters(raw_cluster_config: GitHub.environment.fetch("ES_CLUSTERS", {}).to_s)
  GitHub.es_datacenter = GitHub.environment.fetch("ES_DATACENTER", GitHub::Config::ES_DATACENTER)
  GitHub.es_max_doc_size = GitHub.environment.fetch("ES_MAX_DOC_SIZE", GitHub::Config::ES_MAX_DOC_SIZE).to_i
  GitHub.es_query_timeout = GitHub.environment.fetch("ES_QUERY_TIMEOUT", GitHub::Config::ES_QUERY_TIMEOUT)
  GitHub.es_read_timeout = GitHub.environment.fetch("ES_READ_TIMEOUT", GitHub::Config::ES_READ_TIMEOUT).to_i
  GitHub.es_default_worker_count = GitHub.environment.fetch("ES_DEFAULT_WORKER_COUNT", GitHub::Config::ES_DEFAULT_WORKER_COUNT).to_i
  GitHub.es_shard_count_for_enterprises = GitHub.environment.fetch("ES_SHARD_COUNT_FOR_ENTERPRISES", GitHub::Config::ES_SHARD_COUNT_FOR_ENTERPRISES).to_i
  GitHub.es_shard_count_for_marketplace_listings = GitHub.environment.fetch("ES_SHARD_COUNT_FOR_MARKETPLACE_LISTINGS", GitHub::Config::ES_SHARD_COUNT_FOR_MARKETPLACE_LISTINGS).to_i
  GitHub.es_shard_count_for_repository_actions = GitHub.environment.fetch("ES_SHARD_COUNT_FOR_REPOSITORY_ACTIONS", GitHub::Config::ES_SHARD_COUNT_FOR_REPOSITORY_ACTIONS).to_i
  GitHub.es_shard_count_for_showcases = GitHub.environment.fetch("ES_SHARD_COUNT_FOR_SHOWCASES", GitHub::Config::ES_SHARD_COUNT_FOR_SHOWCASES).to_i
  GitHub.es_shard_count_for_team_discussions = GitHub.environment.fetch("ES_SHARD_COUNT_FOR_TEAM_DISCUSSIONS", GitHub::Config::ES_SHARD_COUNT_FOR_TEAM_DISCUSSIONS).to_i
  GitHub.es_shard_count_for_topics = GitHub.environment.fetch("ES_SHARD_COUNT_FOR_TOPICS", GitHub::Config::ES_SHARD_COUNT_FOR_TOPICS).to_i
  GitHub.es_shard_count_for_vulnerabilities = GitHub.environment.fetch("ES_SHARD_COUNT_FOR_VULNERABILITIES", GitHub::Config::ES_SHARD_COUNT_FOR_VULNERABILITIES).to_i
  GitHub.es_shard_count_for_dependabot_alerts = GitHub.environment.fetch("ES_SHARD_COUNT_FOR_DEPENDABOT_ALERTS", GitHub::Config::ES_SHARD_COUNT_FOR_DEPENDABOT_ALERTS).to_i

  GitHub.file_asset_host = GitHub.environment.fetch("FILE_ASSET_HOST", "/")
  GitHub.file_asset_path = GitHub.environment["FILE_ASSET_PATH"] # TODO: split across configuration: dev and other: (Rails.root + "public"), test: (Rails.root + "test/fixtures/assets#{test_environment_number}"), prod: "/data/assets"

  GitHub.fips_mode = GitHub.environment.fetch_boolean("FIPS_MODE", false)
  GitHub.gitauth_token_hmac_keys = GitHub.environment["GITAUTH_TOKEN_HMAC_KEYS"].to_s.split
  GitHub.githooks_env = GitHub.environment.fetch("GITHOOKS_ENV", GitHub::AppEnvironment.env)
  GitHub.git_daemon_port = GitHub.environment.fetch("GIT_DAEMON_PORT", 9418).to_i
  GitHub.git_lfs_enabled = GitHub.environment.fetch_boolean("GIT_LFS_ENABLED", true)
  GitHub.git_repld_enabled = GitHub.environment.fetch_boolean("GIT_REPLD_ENABLED", false)
  GitHub.platform_graphql_service_tokens = [
    ENV["GRAPHQL_SERVICE_TOKEN"].to_s.split(","), # GRAPHQL_SERVICE_TOKEN is deprecated and is planned to be removed from Proxima
    ENV["LAUNCH_GRAPHQL_SERVICE_TOKEN"].to_s.split(","),
    ENV["PACKAGES_GRAPHQL_SERVICE_TOKEN"].to_s.split(","),
    ENV["DELTAFORCE_SERVICE_TOKEN"].to_s.split(","),
    ENV["GROUP_SYNCER_GRAPHQL_SERVICE_TOKEN"].to_s.split(","),
  ].flatten.freeze
  GitHub.hookshot_enabled = GitHub.environment.fetch_boolean("HOOKSHOT_ENABLED", false)

  # This is required for enterprise where all hookshot-go requests have the namespace of /hookshot.
  GitHub.hookshot_path = GitHub.environment["HOOKSHOT_PATH"]
  GitHub.host_name = GitHub.environment["GH_HOSTNAME"]
  GitHub.identicons_host = GitHub.environment["IDENTICONS_HOST"]

  GitHub.local_datacenter = GitHub.environment["LOCAL_DATACENTER"]
  GitHub.max_render_diffs_per_page = GitHub.environment.fetch("MAX_RENDER_DIFFS_PER_PAGE", 25).to_i
  GitHub.pages_builds_hmac_key = GitHub.environment.fetch("PAGES_BUILDS_HMAC_KEY", "")
  GitHub.pages_enabled = GitHub.environment.fetch_boolean("PAGES_ENABLED", true)
  GitHub.pages_failbot_backend_file_path = GitHub.environment.fetch("PAGES_FAILBOT_BACKEND_FILE_PATH", "#{GitHub::AppEnvironment.root}/log/pages-exceptions.log")

  GitHub.primary_datacenter = GitHub.environment["PRIMARY_DATACENTER"]

  GitHub.private_mode = GitHub.environment["PRIVATE_MODE"]
  GitHub.public_pages = GitHub.environment.fetch_boolean("PUBLIC_PAGES", false)
  GitHub.rate_limiting_enabled = GitHub.environment.fetch_boolean("RATE_LIMITING_ENABLED", false)

  GitHub.registry_enabled_for_enterprise = GitHub.environment.fetch_boolean("REGISTRY_ENABLED_FOR_ENTERPRISE", false)
  GitHub.release_asset_base_path = GitHub.environment.fetch("RELEASE_ASSET_BASE_PATH", "releases")
  GitHub.render_type_filter = GitHub.environment["RENDER_TYPE_FILTER"]
  GitHub.repository_template = GitHub.environment["REPOSITORY_TEMPLATE"]
  GitHub.request_limiting_enabled = GitHub.environment.fetch_boolean("REQUEST_LIMITING_ENABLED", true)

  GitHub.s3_uploads_enabled = GitHub.environment.fetch_boolean("S3_UPLOADS_ENABLED", true)

  GitHub.secret_scanning_enabled = GitHub.environment.fetch_boolean("SECRET_SCANNING_ENABLED", true)

  GitHub.session_key = GitHub.environment["SESSION_KEY"]
  GitHub.signup_enabled = GitHub.environment.fetch_boolean("SIGNUP_ENABLED", nil)
  GitHub.single_instance = GitHub.environment.fetch_boolean("SINGLE_INSTANCE", nil)
  GitHub.smtp_address = GitHub.environment["SMTP_ADDRESS"]
  GitHub.smtp_enabled = GitHub.environment.fetch_boolean("SMTP_ENABLED", true)
  GitHub.smtp_enable_starttls_auto = GitHub.environment.fetch_boolean("SMTP_ENABLE_STARTTLS_AUTO", nil)
  GitHub.ssl = GitHub.environment.fetch_boolean("GH_SSL", true)
  GitHub.ssl_certificate = GitHub.environment["SSL_CERTIFICATE"] ## TODO: condition with test certificate in setter

  GitHub.storage_auto_localhost_replica = GitHub.environment.fetch_boolean("STORAGE_AUTO_LOCALHOST_REPLICA", true)
  GitHub.storage_cluster_enabled = GitHub.environment.fetch_boolean("STORAGE_CLUSTER_ENABLED", false)
  GitHub.storage_cluster_private_assets_enabled = GitHub.environment.fetch_boolean("STORAGE_CLUSTER_PRIVATE_ASSETS_ENABLED", true)

  GitHub.storage_cluster_url = GitHub.environment["STORAGE_CLUSTER_URL"]
  GitHub.storage_private_mode_url = GitHub.environment["STORAGE_PRIVATE_MODE_URL"]
  GitHub.storage_replicate_fmt = GitHub.environment["STORAGE_REPLICATE_FMT"]
  GitHub.storage_replica_count = GitHub.environment["STORAGE_REPLICA_COUNT"].to_i

  GitHub.spokesd_url = GitHub.environment["SPOKESD_URL"]

  GitHub.subdomain_isolation = GitHub.environment.fetch_boolean("SUBDOMAIN_ISOLATION", true)
  GitHub.support_link_type = GitHub.environment.fetch("SUPPORT_LINK_TYPE", "email")

  GitHub.token_scanning_hmac_key = GitHub.environment["TOKEN_SCANNING_HMAC_KEY"]

  # Disable CSP img-src since Enterprise does not have Camo
  GitHub.restrict_external_images = GitHub.environment.fetch_boolean("RESTRICT_EXTERNAL_IMAGES", false)

  # Disable stats collection
  GitHub.browser_stats_enabled = GitHub.environment.fetch_boolean("BROWSER_STATS_ENABLED", false)

  # Allow Git Media on public repos IF Configuration feature flag is set.
  GitHub.alambic_use_media_prefix = GitHub.environment.fetch_boolean("ALAMBIC_USE_MEDIA_PREFIX", true)

  GitHub.flipper_graphql_enabled = GitHub.environment.fetch_boolean("FLIPPER_GRAPHQL_ENABLED", false)
  GitHub.experiments_graphql_enabled = GitHub.environment.fetch_boolean("EXPERIMENTS_GRAPHQL_ENABLED", false)
  GitHub.chatterbox_enabled = false

  # Enable gitbackups when the admin has opted into it
  GitHub.realtime_backups_enabled = GitHub.environment.fetch_boolean("GITBACKUPS_ENABLED", false)

  # Enable the internal Twirp API
  GitHub.twirp_enabled = true

  # We don't require restricted front-ends for devtools, biztools, and stafftools
  # in Enterprise.
  GitHub.admin_frontend_enabled = false

  # In production we should notify failbot when an exception occurs in a unicorn
  # after_response block but not raise.
  GitHub.after_response_raise_on_exception = false

  GitHub.pages_dir = GitHub.environment.fetch("PAGES_DIR", "/data/pages")
end

# Deployment Dashboards, only relevant to GHES
GitHub.deployments_dashboard_enabled = GitHub.environment.fetch_boolean("DEPLOYMENTS_DASHBOARD_ENABLED", false)
# For GHES only, whether admin has enabled passkeys on the instance
GitHub.enterprise_passkeys_enabled = GitHub.environment.fetch_boolean("ENTERPRISE_PASSKEYS_ENABLED", true)
GitHub.enterprise_passkeys_upsell = GitHub.environment.fetch_boolean("ENTERPRISE_PASSKEYS_UPSELL", false)

# Reposd
GitHub.reposd_hmac_key = GitHub.environment.fetch("REPOSD_HMAC_KEY", "octocat")
GitHub.reposd_url = GitHub.environment["REPOSD_URL"]

# Pullsd
GitHub.pullsd_hmac_key = GitHub.environment.fetch("PULLSD_HMAC_KEY", "octocat")
GitHub.pullsd_url = GitHub.environment["PULLSD_URL"]

# Stats middleware
GitHub.stats_middleware_timing_metrics_sample_rate = GitHub.environment.fetch("STATS_MIDDLEWARE_TIMING_METRICS_SAMPLE_RATE", "0.0").to_f
GitHub.stats_middleware_yjit_tracker_metrics_sample_rate = GitHub.environment.fetch("STATS_MIDDLEWARE_YJIT_TRACKER_METRICS_SAMPLE_RATE", "1.0").to_f
GitHub.stats_middleware_gc_tracker_metrics_sample_rate = GitHub.environment.fetch("STATS_MIDDLEWARE_GC_TRACKER_METRICS_SAMPLE_RATE", "1.0").to_f

# Timeout middleware
GitHub.timeout_middleware_timing_metrics_sample_rate = GitHub.environment.fetch("TIMEOUT_MIDDLEWARE_TIMING_METRICS_SAMPLE_RATE", "0.0").to_f

# Redis instrumentation
GitHub.redis_instrumentation_pipeline_stats_sample_rate = GitHub.environment.fetch("REDIS_INSTRUMENTATION_PIPELINE_STATS_SAMPLE_RATE", "0.01").to_f
GitHub.redis_instrumentation_connect_stats_sample_rate = GitHub.environment.fetch("REDIS_INSTRUMENTATION_CONNECT_STATS_SAMPLE_RATE", "0.01").to_f

# Query tracking
GitHub.query_tracking_requests_sample_rate = GitHub.environment.fetch("QUERY_TRACKING_REQUESTS_SAMPLE_RATE", "0.0").to_f

rails_log_stderr = GitHub::Config::Logging.destination == GitHub::Config::Logging::Destination::STDOUT
GitHub.rails_log_stderr = GitHub.environment.fetch("RAILS_LOG_STDERR", rails_log_stderr.to_s) == "true"
ENV["GITHUB_TELEMETRY_PENDING_SPANS_ENABLED"] ||= GitHub.environment.fetch("GITHUB_TELEMETRY_PENDING_SPANS_ENABLED", "false")

GitHub.enqueue_invalid_jobs_per_environment_enabled = GitHub.environment.fetch_boolean("ENQUEUE_INVALID_JOBS_PER_ENVIRONMENT_ENABLED", false)

# Actions JWT Auth
GitHub.actions_jwt_signing_key_pem = GitHub.environment["ACTIONS_JWT_AUTH_PRIMARY_SIGNING_KEY_PEM"]

# RBAC Trino Access
GitHub.spn_dotcom_trino_client_id = GitHub.environment.fetch("SPN_DOTCOM_TRINO_CLIENT_ID", "")
GitHub.spn_dotcom_trino_client_secret = GitHub.environment.fetch("SPN_DOTCOM_TRINO_CLIENT_SECRET", "")
GitHub.spn_dotcom_trino_tenant_id = GitHub.environment.fetch("SPN_DOTCOM_TRINO_TENANT_ID", "")
GitHub.spn_dotcom_trino_object_id = GitHub.environment.fetch("SPN_DOTCOM_TRINO_OBJECT_ID", "")
GitHub.spn_trino_api_endpoint = GitHub.environment.fetch("SPN_TRINO_API_ENDPOINT", "")

# Memory Alpha SPN credentials. All stamps use the same federated keys
GitHub.spn_memory_alpha_tenant_id = GitHub.environment.fetch("SPN_MEMORY_ALPHA_TENANT_ID", "")
GitHub.spn_memory_alpha_client_id = GitHub.environment.fetch("SPN_MEMORY_ALPHA_CLIENT_ID", "")
GitHub.spn_memory_alpha_client_secret = GitHub.environment.fetch("SPN_MEMORY_ALPHA_CLIENT_SECRET", "")

# Copilot Limiter
GitHub.copilot_limiter_url = GitHub.environment.fetch("COPILOT_LIMITER_URL", "http://localhost:2207")
GitHub.copilot_limiter_hmac_key = GitHub.environment.fetch("API_INTERNAL_HMAC_KEYS_FOR_COPILOT_LIMITER", "copilot_limiter_hmac")

# Copilot / Spark Workbench
GitHub.copilot_workbench_aca_management_token = GitHub.environment.fetch("WORKBENCH_ACA_MANAGEMENT_TOKEN", "")
GitHub.copilot_workbench_aca_deployment_token = GitHub.environment.fetch("WORKBENCH_ACA_DEPLOYMENT_TOKEN", "")
GitHub.copilot_workbench_aca_database_token = GitHub.environment.fetch("WORKBENCH_ACA_DATABASE_TOKEN", "")
GitHub.copilot_workbench_aca_jwt_private_key = GitHub.environment.fetch("WORKBENCH_ACA_JWT_PRIVATE_KEY", "")

GitHub.copilot_workbench_snapshot_storage_account = GitHub.environment.fetch("WORKBENCH_SNAPSHOT_STORAGE_ACCOUNT", "sparkworkbench")
GitHub.copilot_workbench_scanning_storage_account = GitHub.environment.fetch("WORKBENCH_SCANNING_STORAGE_ACCOUNT", "sparkscanning")
GitHub.copilot_workbench_spn_client_secret = GitHub.environment.fetch("SPARK_WORKBENCH_SPN_CLIENT_SECRET", "")
GitHub.copilot_workbench_spn_client_id = GitHub.environment.fetch("SPARK_WORKBENCH_SPN_CLIENT_ID", "")
GitHub.copilot_workbench_spn_tenant_id = GitHub.environment.fetch("SPARK_WORKBENCH_SPN_TENANT_ID", "")

# Copilot MCP Client
GitHub.copilot_api_mcp_oauth_jwt_hs512_token = GitHub.environment.fetch("COPILOT_API_MCP_OAUTH_JWT_HS512_TOKEN", "")

# Credential Revocation API
GitHub.credential_revocation_keys = GitHub.environment.fetch("CREDENTIAL_REVOCATION_KEYS", "")

# Compromised credentials encryption keys (parsed once at boot)
GitHub.compromised_credentials_encryption_keys = begin
  JSON.parse(GitHub.environment.fetch("COMPROMISED_CREDENTIALS_ENCRYPTION_KEYS", "{}"))
rescue JSON::ParserError
  {}
end

# GitHub Models
GitHub.github_models_app_key = "Iv23ctfPqVc8gVpaGMLs"

# Proxima Tenant Metadata Service (TMS)
GitHub.proxima_tenant_metadata_url = GitHub.environment.fetch("PROXIMA_TENANT_METADATA_URL", "https://proxima-tenant-metadata-production.service.iad.github.net")
GitHub.proxima_tenant_metadata_hmac_key = GitHub.environment.fetch("METADATA_HMAC_KEYS", "")

# MultiTenantProvisioningRequests internal API
GitHub.api_internal_multi_tenant_provisioning_requests_url = GitHub.environment.fetch("API_INTERNAL_MULTI_TENANT_PROVISIONING_REQUESTS_URL", "https://api.github.com/internal/multi_tenant_provisioning_requests")
