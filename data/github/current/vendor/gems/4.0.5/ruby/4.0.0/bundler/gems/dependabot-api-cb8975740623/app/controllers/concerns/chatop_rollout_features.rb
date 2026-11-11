# frozen_string_literal: true

require "terminal-table"

module ChatopRolloutFeatures
  extend ActiveSupport::Concern

  PERMITTED_ROLLOUT_FEATURES = %w(
    proxy_cached
    enable_private_registry_for_corepack
    allow_refresh_for_existing_pr_dependencies
    allow_refresh_group_with_all_dependencies
    enable_enhanced_error_details_for_updater
    enhanced_grouped_security_error_reporting
    multi_ecosystems
    gradle_lockfile_updater
    enable_exclude_paths_subdirectory_manifest_files
    group_membership_enforcement
    disable_oidc_auth
    docker_pin_digests
  ).freeze

  # rubocop:disable Metrics/BlockLength
  included do
    chatop :rollout_features,
           /rollout[-_\s]features/,
           "rollout features" \
           "- Retrieve the current state of any features being rolled out" do
      unless PERMITTED_ROLLOUT_FEATURES.any?
        jsonrpc_success "No features currently being rolled out."
        return
      end

      features = PERMITTED_ROLLOUT_FEATURES.map do |feature|
        [feature, "#{Dependabot.flipper[feature].percentage_of_actors_value}%"] # rubocop:disable Dependabot/NoLocalFeatureFlags
      end

      table = Terminal::Table.new do |t|
        t.headings = %w(Feature Actors)
        t.rows = features
        t.align_column(1, :right)
        t.style = { border_top: false, border_bottom: false }
      end
      jsonrpc_success(["```", table.to_s, "```"].join("\n"))
    end

    chatop :rollout_feature_actors,
           /rollout[-_\s]feature[-_\s]actors\s+(?<feature>\S+)\s+(?<percentage>.+)/,
           "rollout feature actors FEATURE PERCENTAGE" \
           "- Enable the feature for the specifed percentage of actors" do
      feature = jsonrpc_params[:feature]
      # Support a humanized percentage value by dropping any trailing %
      percentage = jsonrpc_params[:percentage].chomp("%")

      unless PERMITTED_ROLLOUT_FEATURES.include? feature
        jsonrpc_failure "Feature `#{feature}` cannot be managed via chatops."
        return
      end

      rollout(feature, percentage)
    end
  end
  # rubocop:enable Metrics/BlockLength

  def rollout(feature, percentage)
    unless /\A\d+\z/.match?(percentage)
      jsonrpc_failure "Please provide the target percentage as an integer value."
      return
    end

    # rubocop:disable Dependabot/NoLocalFeatureFlags
    Dependabot.flipper[feature].enable_percentage_of_actors(percentage)
    result = Dependabot.flipper[feature].percentage_of_actors_value
    # rubocop:enable Dependabot/NoLocalFeatureFlags

    jsonrpc_success(
      "#{feature} is now enabled for #{result}% of actors"
    )
  end
end
