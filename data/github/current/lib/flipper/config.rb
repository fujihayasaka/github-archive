# typed: true
# frozen_string_literal: true

require "flipper"
require "flipper/adapters"
require "github/config/notifications"
require "github/config/memcache"

module Flipper
  class Config
    BIG_FEATURES = %w(
      actions_required_workflows_on_demand_app_installation
      block_compromised_password_at_sign_in_opt_out
      code_scanning_disable_python_dependency_installation_disabled
      code_scanning_ml_powered_queries
      codespaces_billing_free
      codespaces_developer
      codespaces_prebuild_billing_free
      copilot_chat_jetbrains
      copilot_code_review_public_preview
      copilot_code_review_v1
      copilot_for_business_free
      copilot_for_partners
      copilot_hadron_editor
      copilotignore
      gh_migrator_import_to_dotcom
      ignorable_team_notifications
      insights_publish_enabled
      ipynb-diff
      launch_lab
      mannequin_claiming
      memex_insights
      memex_table_without_limits
      merge_queue
      octoshift_bitbucket_server
      okta_team_sync
      org_credential_authorizations_api_all_oauth_tokens
      packages_docker_v1_migration_in_process
      packages_docker_v1_migration_pending
      packages_maven_registry_v2
      security_center_ghas_insights
      tasklist_block
      verified_device_enforcement_opt_out
      workspaces
    )

    def self.big_features
      GitHub.enterprise? ? [] : BIG_FEATURES
    end

    def self.in_memory_enabled?
      ENV["FLIPPER_IN_MEMORY_ENABLED"] == "1"
    end

    # Since the feature-flag-hub forwarder cannot be used in unit tests and all feature flags are enabled by default in CI tests, this environment variable
    # is used to disable the feature-flag-hub forwarder in tests and by default on review lab deployments. This value is set in proxima and dotcom in the Vault if enabled
    def self.feature_flag_hub_forwarder_enabled?
      return true if ENV["FEATURE_FLAG_HUB_FORWARDER_ENABLED"] == "1"
      return true if GitHub.use_fm_lite?
      false
    end

    def self.enabled_adapter
      # Don't run in memory flipper outside of unicorn and don't run in gitauth
      # We saw elevated errors and issues connecting to gitauth servers by job servers during a previous deploy.
      # To mitigate and simplify I am disabling the new adapter on gitauth for now.
      # We can look at re-enabling it later.
      #
      if in_memory_enabled? && GitHub.component == :unicorn && GitHub.role != :gitauth
        dual_adapter
      else
        lazy_memcached_adapter
      end
    end

    def self.dual_adapter
      @dual_adapter ||= ::Flipper::Adapters::Dual.new(in_memory_adapter, lazy_memcached_adapter)
    end

    def self.in_memory_adapter
      @in_memory_adapter ||= ::Flipper::Adapters::InMemory.new(lazy_memcached_adapter, big_features: big_features)
    end

    def self.lazy_memcached_adapter
      @lazy_memcached_adapter ||= ::Flipper::Adapters::LazyActors.new(memcached_adapter, big_features)
    end

    def self.memcached_adapter
      @memcached ||= ::Flipper::Adapters::Memcacheable.new(mysql_adapter, GitHub.cache)
    end

    def self.mysql_adapter
      return @mysql if defined?(@mysql)

      mysql = ::Flipper::Adapters::Mysql.new(self.feature_flag_hub_forwarder_enabled?, exclude_actors_for: big_features)
      mysql = ::Flipper::Adapters::InstrumentedWithLazy.new(mysql, instrumenter: GitHub.instrumentation_service)
      if ENV["TEST_ALL_FEATURES"] && !ENV["TEST_TIMERD"]
        mysql = ::Flipper::Adapters::EnabledByDefault.new(mysql)

        # The exclusion list moved to lib/feature_flag/all_features.rb
        # The exclusion list will be used by both Flipper and Vexi while we migrate between systems.
        FeatureFlag::AllFeatures.exclusion_list.each do |feature|
          mysql.exclude(feature)
        end
      end

      @mysql = mysql
    end
  end
end
