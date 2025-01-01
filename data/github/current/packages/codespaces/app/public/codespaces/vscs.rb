# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  class Vscs
    # Codespaces feature flags that are proxied to VSCS
    # Should flag in based on the codespace's *owner*
    OWNER_FEATURE_FLAGS = %w[
      codespaces_developer
      codespaces_detailed_activity_monitor
      codespaces_vscode_account_switching
      codespaces_enable_smb_diagnostic_continuous_monitoring
      codespaces_enable_smb_diagnostic_on_anomaly_monitoring
      codespaces_use_early_workbench_web_client
      codespaces_use_coi_web_client
      codespaces_remap_user_namespace
      codespaces_remove_connect_retries_web_client
      codespaces_storage_v2_exhaustive_validation
      codespaces_force_push_shutdown_telemetry
      codespaces_use_new_jupyter_api
      codespaces_improved_warmup_container_reuse
      codespaces_storage_v2_comprehensive_diagnostics_collection
      codespaces_using_copilot_workspace_config
      copilot_workspace
      codespaces_hostname_specific_git_credential_helper
    ]

    # Codespaces feature flags that are proxied to VSCS
    # Should flag in based on the codespace's *billable owner*
    BILLABLE_OWNER_FEATURE_FLAGS = %w[
      codespaces_enforce_image_allow_list_in_agent
      codespaces_docker_authz_plugin
      codespaces_enable_gvisor_for_preventing_container_escapes
    ]

    # Codespaces feature flags that are proxied to the prebuild runner
    # Should flag in based on the *repository*
    PREBUILD_FEATURE_FLAGS = %w[
      codespaces_remap_user_namespace
      codespaces_storage_v2_docker_lib_sku_size
      codespaces_storage_v2_docker_lib_sku_size_ppe
      codespaces_storage_v2_docker_lib_sku_size_development
      codespaces_storage_v2_docker_lib_sku_size_local
    ]

    # Based on https://devdiv.visualstudio.com/DefaultCollection/OnlineServices/_git/vsclk-core?path=/src/Codespaces/EnvironmentManager/Src/EnvironmentManager.Contracts/CloudEnvironmentState.cs.
    #
    # The order should be the same as the above file to make it easier to ensure
    # they match.
    module State
      UNKNOWN = "Unknown"
      CREATED = "Created"
      QUEUED = "Queued"
      PROVISIONING = "Provisioning"
      AVAILABLE = "Available"
      AWAITING = "Awaiting"
      UNAVAILABLE = "Unavailable"
      DELETED = "Deleted"
      MOVED = "Moved"
      SHUTDOWN = "Shutdown"
      ARCHIVED = "Archived"
      STARTING = "Starting"
      SHUTTING_DOWN = "ShuttingDown"
      FAILED = "Failed"
      EXPORTING = "Exporting"
      UPDATING = "Updating"
      REBUILDING = "Rebuilding"

      # This should includes all the states above.
      ALL_STATES = [
        UNKNOWN,
        CREATED,
        QUEUED,
        PROVISIONING,
        AVAILABLE,
        AWAITING,
        UNAVAILABLE,
        DELETED,
        MOVED,
        SHUTDOWN,
        ARCHIVED,
        STARTING,
        SHUTTING_DOWN,
        FAILED,
        EXPORTING,
        UPDATING,
        REBUILDING,
      ]

      # The states in which we consider an environment to be consuming compute.
      #
      # Based on https://devdiv.visualstudio.com/DefaultCollection/OnlineServices/_git/vsclk-core?path=/src/Codespaces/EnvironmentManager/Src/EnvironmentManager/EnvironmentManager.cs&version=GBmain&line=1193&lineEnd=1216&lineStartColumn=1&lineEndColumn=1&lineStyle=plain&_a=contents
      # but importantly omitting the SHUTTING_DOWN state so that we don't count
      # codespaces that we're already shutting down against our limits.
      CONSUMING_COMPUTE_STATES = [
        UNKNOWN,
        CREATED,
        QUEUED,
        PROVISIONING,
        AVAILABLE,
        AWAITING,
        UNAVAILABLE,
        STARTING,
      ]

      # The states where calling the vscs start api would be a noop

      # see https://github.com/microsoft/vssaas-planning/issues/2452

      ALREADY_STARTED_STATES = [
        AVAILABLE,
        STARTING,
      ]
    end

    SLOW_BILLING_QUEUE_NAMES = %w[vsoprodrelasseghasse vsoprodreleuwgheuw vsoprodrelincghinc].freeze

    LOCAL_URI_HOST = "codespaces.servicebus.windows.net"

    class TargetConfig
      include ActiveModel::API

      attr_accessor :name, :display_name, :api_url, :pfs_auth_postback_host, :web_portal_url_format, :dev_tunnels_domain

      def self.for(vscs_target)
        new(Codespaces::Vscs.config_for_target(vscs_target&.to_sym))
      rescue KeyError
        nil
      end

      def to_s
        name.to_s
      end

      def ==(other)
        other = self.class.for(other) if other.is_a?(Symbol)

        self.class == other.class && name == other.name
      end
      alias_method :eql?, :==

      delegate :inquiry, to: :to_s
      delegate :production?, :ppe?, :development?, to: :inquiry
    end

    MIN_IDLE_TIME = 5.minutes.freeze
    MAX_IDLE_TIME = 4.hours.freeze

    def self.target_configs
      GitHub::Config::VSCS_ENVIRONMENTS
    end

    def self.targets
      target_configs.keys
    end

    def self.valid_target_for_provisioning?(target)
      target_configs.key?(target)
    end

    def self.default_target_config
      GitHub.codespaces_vscs_environment
    end

    def self.default_target
      default_target_config[:name]
    end

    def self.config_for_target(vscs_target)
      target_configs.fetch(vscs_target)
    end

    def self.available_vscs_target_configs(user)
      user.feature_enabled?(:codespaces_developer) ? Codespaces::Vscs.target_configs.values : []
    end

    def self.dev_tunnels_domain_for_target(vscs_target)
      config = self.config_for_target(vscs_target)
      config[:dev_tunnels_domain] % { second_level_domain: GitHub.codespaces_web_portal_second_level_domain }
    end

    def self.web_portal_url_formats
      target_configs.map { |_, config| config[:web_portal_url_format] }
    end

    def self.valid_local_target_url?(repository:, vscs_target:, vscs_target_url:)
      return true unless GitHub.flipper[:codespaces_local_target_url_valid].enabled?(repository) && vscs_target == :local

      if vscs_target_url.blank?
        return false
      end

      current_uri_host = URI.parse(vscs_target_url).host
      dev_uri_host = URI.parse(GitHub::Config::VSCS_ENVIRONMENTS[:development][:api_url]).host
      latest_dev_uri_host = URI.parse(GitHub::Config::VSCS_ENVIRONMENTS[:latestdev][:api_url]).host

      [LOCAL_URI_HOST, dev_uri_host, latest_dev_uri_host].include?(current_uri_host)
    end

    def self.prebuild_feature_flags(repository)
      Hash[format_feature_flags(PREBUILD_FEATURE_FLAGS, repository)]
    end

    def self.use_storage_v2?(repo:, current_user:, sku_name:, billable_owner:)
      # If the repo is disallowed from using Storage v2 then nothing else matters.
      is_disallowed = GitHub.flipper[:codespaces_storage_v2_disallowed].enabled?(repo)
      return false if is_disallowed

      # Being enabled on both the repo and the user takes precedence over all other checks.
      is_soft_enabled = GitHub.flipper[:codespaces_use_storage_v2].enabled?(repo) && GitHub.flipper[:codespaces_use_storage_v2].enabled?(current_user)
      return true if is_soft_enabled

      # If the SKU is specifically disabled then don't use Storage v2 yet, regardless of whether we're rolling out to
      # the repo or org below.
      is_enabled_for_sku = if sku_name == "standardLinux32gb"
        !GitHub.flipper[:codespaces_storage_v2_4_core_sku_reject].enabled?(repo)
      elsif sku_name == "basicLinux32gb"
        !GitHub.flipper[:codespaces_storage_v2_2_core_sku_reject].enabled?(repo)
      else
        true
      end
      return false unless is_enabled_for_sku

      # Find the "topmost" entity against which to check feature flags, meaning the business if there is one and the
      # billable owner otherwise (which will be either an org or the user).
      feature_flag_entity = billable_owner&.business || billable_owner || current_user

      is_force_enabled = GitHub.flipper[:codespaces_force_storage_v2].enabled?(feature_flag_entity) || GitHub.flipper[:codespaces_force_storage_v2].enabled?(repo)
      return true if is_force_enabled

      # We can do a percentage-based rollout on either the repo (e.g., gh/gh) or the toplevel entity
      # (e.g., github business).
      is_entity_being_rolled_out = GitHub.flipper[:codespaces_use_storage_v2_percentage_based_rollout].enabled?(repo) || GitHub.flipper[:codespaces_use_storage_v2_percentage_based_rollout].enabled?(feature_flag_entity)
      return false unless is_entity_being_rolled_out

      is_user_in_bucket = GitHub.flipper[:codespaces_use_storage_v2_percentage_based_rollout_buckets].enabled?(current_user)
      is_user_in_bucket
    end

    def self.feature_flags(owner, billable_owner = nil)
      # Flags set for the user of the codespace
      owner_flags = format_feature_flags(OWNER_FEATURE_FLAGS, owner)
      # Override certain flag values when in multi_tenant_enterprise
      if GitHub.multi_tenant_enterprise?
        vscode_account_switching_formatted_flag = format_feature_flag("codespaces_vscode_account_switching")
        flag_index = owner_flags.index { |flag| flag[0] == vscode_account_switching_formatted_flag }
        owner_flags[flag_index] = [vscode_account_switching_formatted_flag, true]
      end
      # Flags set for the billable_owner of the codespace
      billable_owner_flags = if !GitHub.flipper[:codespaces_proxy_billable_owner_flags_to_vscs].enabled?(nil) || billable_owner.nil?
        []
      else
        format_feature_flags(BILLABLE_OWNER_FEATURE_FLAGS, billable_owner)
      end

      # NOTE: 'owner' flags take precedence over 'billable_owner' flags
      Hash[billable_owner_flags + owner_flags]
    end

    def self.format_feature_flag(flag)
      flag.remove("codespaces_").camelize(:lower)
    end

    def self.format_feature_flags(array, actor)
      array.collect do |flag|
        [format_feature_flag(flag), GitHub.flipper[flag].enabled?(actor)]
      end
    end
  end
end
