# typed: false
# frozen_string_literal: true

# GitHub Enterprise configuration
# This file is loaded instead of production.rb when running in the
# production environment in GitHub Enterprise mode (FI=1).

# The below is needed primarily for GitHub.gravatar_asset_url.
require "github/config/environments/default"

if GitHub::AppEnvironment.production?
  GitHub.repository_template = GitHub.environment.fetch("REPOSITORY_TEMPLATE", "/data/github/current/lib/git-core/fi-template".freeze)
else
  GitHub.repository_template = GitHub.environment.fetch("REPOSITORY_TEMPLATE", "#{GitHub::AppEnvironment.root}/lib/git-core/fi-template".freeze)
end

GitHub.hookshot_token = (ENV["HOOKSHOT_TOKEN"] || "hookshot-test-token")

# Default, but probably changed by ENTERPRISE_ALAMBIC_PATH_PREFIX
# TODO(storage): deprecated by alambic cluster
GitHub.alambic_path_prefix = "avatars"

# Disable CSP connect-src support for third party sources since Enterprise is
# not supposed to contact third parties URLs (except in cluster mode, Enterprise 2.4+).
#
# Enabled by ENTERPRISE_ALLOW_THIRD_PARTY_CONNECT_SOURCES.
GitHub.allow_third_party_connect_sources = false

# Set all ENTERPRISE_XXX environment variables on the GitHub module.
# Example variables from sulu.githubapp.com:
#     ENTERPRISE_SESSION_KEY=_fi_sess
#     ENTERPRISE_SMTP_PORT=23
#     ENTERPRISE_SMTP_PASSWORD=syvsdxc5n...
#     ENTERPRISE_HOST_NAME=sulu.githubapp.com
#     ENTERPRISE_SMTP_USER_NAME=ac58299
#     ENTERPRISE_SESSION_SECRET=222eecc46f5b502bad4a1720063ab7783e14c2407e71...
#     ENTERPRISE_SSL=true
#     ENTERPRISE_SOLR_SERVER=127.0.0.1:8983
#     ENTERPRISE_UNLIMITED_SEATING=true
#     ENTERPRISE_PERPETUAL=true
#     ENTERPRISE_SMTP_DOMAIN=sulu.githubapp.com
#     ENTERPRISE_SMTP_ADDRESS=mail.authsmtp.com
#     ENTERPRISE_SMTP_AUTHENTICATION=plain
#     ENTERPRISE_CONFIGURATION_ID=1319413500
#     ENTERPRISE_PRIVATE_MODE=
#     ENTERPRISE_SUBDOMAIN_ISOLATION=
#
casts = GitHub::Config::PrefixEnvironment::BOOLEAN_CASTS
fixnums = %w[
  configuration_id smtp_port ldap_port rails_log_level
  es_shard_count_for_audit_log
  es_shard_count_for_code_search
  es_shard_count_for_commits
  es_shard_count_for_issues
  es_shard_count_for_notifications
  es_shard_count_for_pull_requests
  es_shard_count_for_releases
  es_shard_count_for_repos
  es_shard_count_for_users
  es_shard_count_for_topics
  es_shard_count_for_labels
  es_shard_count_for_discussions
  es_shard_count_for_team_discussions
  es_shard_count_for_showcases
  es_shard_count_for_gists
  es_shard_count_for_wikis
  es_shard_count_for_projects
  es_shard_count_for_marketplace_listings
  es_shard_count_for_non_marketplace_listings
  es_shard_count_for_repository_actions
  es_shard_count_for_registry_packages
  es_shard_count_for_vulnerabilities
  es_shard_count_for_enterprises
  es_shard_count_for_workflow_runs
  es_number_of_replicas es_max_doc_size
  es_read_timeout es_open_timeout es_default_worker_count
  ldap_user_sync_interval ldap_team_sync_interval ldap_tls_verify_mode
  max_render_diffs_per_page dgit_git_daemon_port dgit_copies dgit_non_voting_copies
  pages_replica_count pages_non_voting_replica_count desktop_fetch_interval
  storage_replica_count storage_non_voting_replica_count ldap_auth_timeout
  write_only_to_healthy_replicas
  authentication_fingerprint_by_path_max graphql_authentication_fingerprint_max elapsed_time_by_authentication_fingerprint_max elapsed_authenticated_time_by_path_graphql_max
  search_elapsed_time_max search_elapsed_time_ttl concurrent_authentication_fingerprint_max concurrent_authentication_fingerprint_ttl
  search_ip_address_max search_ip_address_ttl requests_by_pat_max
  api_unauthenticated_rate_limit api_default_rate_limit
  api_audit_log_unauthenticated_rate_limit api_audit_log_default_rate_limit api_audit_log_streaming_unauthenticated_rate_limit api_audit_log_streaming_default_rate_limit
  api_search_default_rate_limit api_search_unauthenticated_rate_limit
  api_lfs_default_rate_limit api_lfs_unauthenticated_rate_limit
  api_graphql_default_rate_limit api_graphql_unauthenticated_rate_limit
  api_graphql_higher_rate_limit
  user_session_access_throttling
  user_session_timeout
  lfs_integrity_max_oids
  duplicate_head_sha_limit
  assignees_list_limit
  secret_scanning_max_scans_per_repo
  secret_scanning_max_custom_patterns_per_repo
  secret_scanning_max_custom_patterns_per_org
  secret_scanning_max_custom_patterns_per_business
  secret_scanning_max_post_processing_expressions_per_pattern
  secret_scanning_max_backfill_scans
  secret_scanning_max_incremental_scans
  secret_scanning_max_candidate_matches
  secret_scanning_max_dry_run_results
  secret_scanning_max_dry_run_selected_repositories
  scanning_scheduler_interval
  bcrypt_password_cost
  pbkdf2_iterations
  argon2_time_cost
  argon2_memory_cost
  saml_default_session_expiration
  checks_retention_archive_threshold
  checks_retention_delete_threshold
  max_orgs_per_et_org_reconciliation_runner
  max_concurrent_et_org_reconciliation_runners
  max_concurrent_background_instrumentation_jobs
]

# some attributes are treated as arrays
arrays = %w[
  api_internal_aleph_hmac_keys
  api_internal_assets_hmac_keys
  api_internal_assets_uploadable_hmac_keys
  api_internal_avatars_hmac_keys
  api_internal_email_bounce_hmac_keys
  api_internal_gists_hmac_keys
  api_internal_lfs_hmac_keys
  api_internal_marketplace_analytics_hmac_keys
  api_internal_media_app_hmac_keys
  api_internal_multi_part_policies_hmac_keys
  api_internal_porter_callbacks_hmac_keys
  api_internal_pre_receive_hooks_hmac_keys
  api_internal_raw_hmac_keys
  api_internal_archive_hmac_keys
  api_internal_repositories_hmac_keys
  api_internal_storage_uploadable_hmac_keys
  api_internal_twirp_hmac_keys
  actions_runner_ip_ranges
  gitauth_token_hmac_keys
  maccloud_ips
  rate_limiting_exempt_users
  stats_hosts
  user_password_secrets
]


# some attributes really need some special behavior
no_cast_attributes = %w[
  saml_sp_pkcs12_password
]

# Set the request to the unicorn timeout (30s) - 2s. See config/unicorn.rb.
GitHub.default_request_timeout = 28

# Allow 5.0 seconds for slow requests on Enterprise
GitHub.slow_request_threshold = 5.0

GitHub.stats_hosts = ["127.0.0.1:8125"]

ENV.each do |key, value|
  next if key !~ /^ENTERPRISE_/
  config_key = key.sub("ENTERPRISE_", "").downcase
  next if value.empty? && !no_cast_attributes.include?(config_key)
  next if !GitHub.respond_to?("#{config_key}=")

  value =
    if fixnums.include?(config_key)
      value.to_i
    elsif arrays.include?(config_key)
      value.to_s.split
    elsif config_key == "es_clusters"
      GitHub.parse_es_clusters(raw_cluster_config: value.to_s)
    elsif casts.key?(value) && !no_cast_attributes.include?(config_key)
      casts[value]
    else
      value
    end
  GitHub.send "#{config_key}=", value
end

# Conditionally set user content host
GitHub.user_content_host_name ||= GitHub.host_name

# Disable CSP img-src since Enterprise does not have Camo
GitHub.restrict_external_images = false

# Use a separate session cookie in development so that switching between
# enterprise and .com is sane and doesn't overwrite the other's session.
if GitHub::AppEnvironment.development?
  GitHub.session_key = "_gh_ent"
end

if GitHub::AppEnvironment.production?
  GitHub.rails_log_level = :info
  # GHES Rails logs: https://github.com/github/observability/issues/3049
  GitHub.rails_log_stderr = GitHub.environment.fetch("RAILS_LOG_STDERR", "false") == "true"

  if GitHub.subdomain_isolation?
    GitHub.pages_host_name_v2 = "pages.#{GitHub.host_name}"
    GitHub.gist_host_name = "gist.#{GitHub.host_name}"
    GitHub.gist3_host_name = "gist.#{GitHub.host_name}"
    GitHub.asset_host_url = GitHub.environment.fetch("ASSET_HOST_URL", "assets.#{GitHub.host_name}")
  end
end

# Gist
# TODO: These ENV variables match the naming conventions in Gist Web.
# We should migrate these to the `ENTERPRISE_` convention once we
# drop the `gist3` prefix in favor of the `gist` prefix.
GitHub.gist_oauth_client_id  = ENV["GIST_OAUTH_CLIENT_ID"]
GitHub.gist_oauth_secret_key = ENV["GIST_OAUTH_SECRET"]

# Disable stats collection
GitHub.browser_stats_enabled = false

# Allow Git Media on public repos IF Configuration feature flag is set.
GitHub.alambic_use_media_prefix = true

GitHub.stats_allowlist = %w(
  unicorn.{browser,anon,ajax,poll,api,robot,raw,atom,other}.response_time
  unicorn.{browser,anon,ajax,poll,api,robot,raw,atom,other}.status_code.*.count
  unicorn.{browser,anon,ajax,poll,api,robot,raw,atom,other}.{cpu_time,idle_time}
  unicorn.{browser,anon,ajax,poll,api,robot,raw,atom,other}.{marshal,zlib,es,redis,gitrpc,mysql,memcached}.{queries,time}
  unicorn.{browser,anon,ajax,poll,api,robot,raw,atom,other}.gc.{time,major,minor,allocations,collections}
  exception.github.count
  git.hooks.pre_receive.custom.timing
  git_maintenance.{network,gist}.count.{needed,scheduled,running,failed,spurious_failure,retry,broken}
  dgit.3pc.timing
  dgit.*.{repos,networks,gists}.{cleanup,failed,bad-checksum,no-checksum}.count
  dgit.*.actions.{create,destroy,repair}*.{timing,count}
  dgit.*.rpc-error
  dgit.*.liveness_check.{timing,up,sketchy,down}
  dgit.*maintenance-queries
  dgit.queries.*.time.*
  ldap.sync.*.{runtime,total}
  ldap.authenticate.*
  auth.result.*
  private_instance.usage.*
  public_key.access.count
  integration_client_secret.access.count
  oauth_application_client_secret.access.count
  memcached.*
  github_connect_search.*
  github_connect_contributions.*
  github_connect_connection.*
  secret_scanning.jobs.{public,private}_{repo,commit}_{errors}_{timeout,command_failed,stop_retry,max_candidates,invalid_repository}
  secret_scanning.jobs.{public,private}_{repo,commit}_latency
  hydro_client.sink.message_dropped.*
  github.stream_processor.message.*
  github.stream_processor.process.*
)
GitHub.stats_allowlist += ENV["ENTERPRISE_STATS_WHITELIST"].split(";") if ENV["ENTERPRISE_STATS_WHITELIST"]

# Disable GitHub Pages size limit
GitHub.pages_site_size_limit = 0

GitHub.flipper_graphql_enabled = false
GitHub.flipper_ui_enabled = false
GitHub.experiments_graphql_enabled = false
GitHub.chatterbox_enabled = false
GitHub.datadog_enabled = false

# Ignore these index settings when comparing an index version.
# In enterprise, auto_expand_replicas is always set and number_of_replicas
# shouldn't be used to decide if the index version has changed.
GitHub.es_skip_settings_fields = %i(number_of_replicas auto_expand_replicas)

# Enable gitbackups when the admin has opted into it
GitHub.realtime_backups_enabled = GitHub.environment.fetch("ENTERPRISE_GITBACKUPS", "false") == "true"

GitHub.platform_graphql_service_tokens = [
  ENV["ENTERPRISE_GRAPHQL_SERVICE_TOKEN"].to_s.split(","),
].flatten.freeze

# load the shared hmac key for internal api requests
GitHub.internal_api_hmac_keys = [ENV["ENTERPRISE_INTERNAL_API_HMAC_KEY"]] if ENV["ENTERPRISE_INTERNAL_API_HMAC_KEY"]

# Enable the internal Twirp API
GitHub.twirp_enabled = true

# We don't require restricted front-ends for devtools, biztools, and stafftools
# in Enterprise.
GitHub.admin_frontend_enabled = false

# In production we should notify failbot when an exception occurs in a unicorn
# after_response block but not raise.
GitHub.after_response_raise_on_exception = false

# GitHub Telemetry logging config
# We never want to write to a file in containers
ENV["GITHUB_TELEMETRY_LOGS_FILE"] = "false"
# By default all programs will write to the `/proc/1/fd/1` file descriptor, which is the root process of the container.
# if it is unable to write to the root process `/proc/1/fd/1` it will write to `/dev/stdout`
ENV["GITHUB_TELEMETRY_LOGS_STDOUT"] ||= "true"
# We never want to write to syslog in containers
ENV["GITHUB_TELEMETRY_LOGS_SYSLOG"] = "false"
# Set log level to "info"
ENV["GITHUB_TELEMETRY_LOGS_LEVEL"] ||= "info"
# Set Hydro log level to info. Used in lib/hydro_loader.rb to initializer Hydro.logger for usage from Hydro gem code and Kafka producer and consumer logging.
ENV["HYDRO_CONSUMER_LOG_LEVEL"] ||= "info"
ENV["HYDRO_PUBLISHER_LOG_LEVEL"] ||= "info"

if (configured_limit = ENV["ENTERPRISE_JOB_WORKER_GRACEFUL_MEMORY_LIMIT_IN_MB"])
  GitHub.job_worker_graceful_memory_limit = configured_limit.to_i * 1024 * 1024
else
  # This is used for capping the memory usage of a worker process if we don't define it anywhere else.
  # We should make this more dynamic for enterprise given the constraints of the environment and the limited observability
  # This avoids memory leaks on worker processes so the max memory allowed is quite conservative.
  GitHub.job_worker_graceful_memory_limit = 5120 * 1024 * 1024
end

GitHub.enqueue_invalid_jobs_per_environment_enabled = GitHub.environment.fetch("ENTERPRISE_ENQUEUE_INVALID_JOBS_PER_ENVIRONMENT", "false") == "true"
