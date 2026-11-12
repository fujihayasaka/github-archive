# frozen_string_literal: true

require "terminal-table"

module ChatopRepoFeatures # rubocop:disable Metrics/ModuleLength
  extend ActiveSupport::Concern

  # NOTE: job_sqs_stage controls runner environment (stage vs prod)
  PERMITTED_REPO_FEATURES = %w(
    actions_long_timeout
    actions_timeout_1_minute
    automerge
    autofix_demo
    debug_logging
    dependabot_paused_test_24_hours
    dependabot_paused_test_immediate
    ghes_mode
    job_sqs_stage
    new_merge_command
    nuget_use_single_restore
    proxy_cached
    shared_workspace
    threaded_metadata_updates
    timeout_per_operation
    use_global_app_for_access_tokens
    enable_record_ecosystem_meta
    enable_corepack_for_npm_and_yarn
    enable_private_registry_for_corepack
    enable_shared_helpers_command_timeout
    avoid_duplicate_updates_package_json
    allow_refresh_for_existing_pr_dependencies
    allow_refresh_group_with_all_dependencies
    enable_enhanced_error_details_for_updater
    enhanced_grouped_security_error_reporting
    multi_ecosystems
    gradle_lockfile_updater
    enable_exclude_paths_subdirectory_manifest_files
    group_membership_enforcement
    deprecate_close_command
    deprecate_reopen_command
    deprecate_merge_command
    deprecate_cancel_merge_command
    deprecate_squash_merge_command
    disable_close_command
    disable_reopen_command
    disable_merge_command
    disable_cancel_merge_command
    disable_squash_merge_command
    disable_oidc_auth
    automatic_github_packages_auth
    docker_pin_digests
  ).freeze

  # rubocop:disable Metrics/BlockLength
  included do
    chatop :repo_features,
           /repo[-_\s]features\s+(?<github_nwo>.+)/,
           "repo features NWO [--tenant TENANT] " \
           "- Retrieve the enabled features for the specified repo" do
      github_nwo = jsonrpc_params[:github_nwo]
      if github_nwo.include?("enable ") || github_nwo.include?("disable ")
        jsonrpc_failure "Did you mean `.dependabot repo feature #{github_nwo}`?"
        return
      end

      tenant = jsonrpc_params[:tenant]
      repo = find_by_nwo!(github_nwo, tenant)
      features = PERMITTED_REPO_FEATURES.map do |feature|
        [
          feature,
          repo.feature_enabled?(feature),
          repo.account.feature_enabled?(feature),
        ]
      end

      table = Terminal::Table.new do |t|
        t.headings = %w(Feature Enabled? Account?)
        t.rows = features
        t.align_column(1, :right)
        t.align_column(2, :right)
        t.style = { border_top: false, border_bottom: false }
      end
      jsonrpc_success(["```", table.to_s, "```"].join("\n"))
    end

    chatop :repo_feature_enable,
           /repo[-_\s]feature[-_\s]enable\s+(?<github_nwo>\S+)\s+(?<feature>.+)/,
           "repo feature enable NWO FEATURE [--tenant TENANT] " \
           "- Enable feature for the specified nwo" do
      github_nwo = jsonrpc_params[:github_nwo]
      feature = jsonrpc_params[:feature]

      unless PERMITTED_REPO_FEATURES.include? feature
        jsonrpc_failure "Feature `#{feature}` cannot be managed via chatops."
        return
      end

      tenant = jsonrpc_params[:tenant]
      repo = find_by_nwo!(github_nwo, tenant)
      repo.enable_feature(feature)
      jsonrpc_success "Successfully enabled `#{feature}` on `#{github_nwo}`"
    end

    chatop :repo_feature_disable,
           /repo[-_\s]feature[-_\s]disable\s+(?<github_nwo>\S+)\s+(?<feature>.*)/,
           "repo feature disable NWO FEATURE [--tenant TENANT] " \
           "- Disable feature for the specified nwo" do
      github_nwo = jsonrpc_params[:github_nwo]
      feature = jsonrpc_params[:feature]

      unless PERMITTED_REPO_FEATURES.include? feature
        jsonrpc_failure "Feature `#{feature}` cannot be managed via chatops."
        return
      end

      tenant = jsonrpc_params[:tenant]
      repo = find_by_nwo!(github_nwo, tenant)
      repo.disable_feature(feature)
      jsonrpc_success "Successfully disabled `#{feature}` on `#{github_nwo}`"
    end
  end
  # rubocop:enable Metrics/BlockLength
end
