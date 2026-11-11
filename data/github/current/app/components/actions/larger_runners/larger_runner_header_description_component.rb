# typed: strict
# frozen_string_literal: true

module Actions
  class LargerRunners::LargerRunnerHeaderDescriptionComponent < ApplicationComponent
    include ::Actions::LargerRunnersHelper
    include NetworkConfigurationsHelper

    sig do
      params(
        larger_runner: Actions::LargerRunner,
        owner_settings: T.any(EnterpriseRunnersView, OrgRunnersView),
        owner: T.any(Organization, Business),
        network_configuration_name: String,
        image_gen_feature_enabled: T::Boolean
      ).void
    end
    def initialize(larger_runner:, owner_settings:, owner:, network_configuration_name: "",  image_gen_feature_enabled: false)
      @larger_runner = larger_runner
      @owner_settings = owner_settings
      @owner = owner
      @network_configuration_name = network_configuration_name
      @image_gen_feature_enabled = image_gen_feature_enabled
    end

    sig { returns(Actions::RunnerGroup) }
    def runner_group
      @larger_runner.runner_group(@owner_settings.settings_owner)
    end

    sig { returns(String) }
    def runner_group_name
      @larger_runner.runner_group_name(@owner_settings.settings_owner)
    end

    sig { returns(T.nilable(String)) }
    def runner_image_source
      image_source_for(@larger_runner)
    end

    sig { returns(T::Boolean) }
    def runner_image_source_is_alpha
      image_source_is_alpha_for(@larger_runner)
    end

    sig { returns(T::Boolean) }
    def runner_image_source_is_custom
      image_source_is_custom_for(@larger_runner)
    end

    sig { returns(String) }
    def runner_custom_image_path
      @larger_runner.runner_custom_image_path(@owner_settings)
    end

    sig { returns(String) }
    def runner_custom_image_definition_path
      @larger_runner.runner_custom_image_definition_path(@owner_settings)
    end

    sig { returns(T.nilable(String)) }
    def runner_image_name
      image_name_for(@larger_runner, @owner)
    end

    sig { returns(Actions::MachineSpec) }
    def runner_machine_spec
      return @larger_runner.machine_spec unless @larger_runner.machine_spec.nil?

      Actions::MachineSpec.new(
        cpu_cores: nil,
        memory_gb: nil,
        storage_gb: nil,
        id: @larger_runner.machine_spec_id)
    end

    sig { returns(T.nilable(String)) }
    def runner_platform_name
      platform_name_for(@larger_runner)
    end

    sig { returns(T::Boolean) }
    def should_disable_public_ip
      @larger_runner.is_public_ip_enabled && !is_public_ip_allowed_for_entity?(@owner)
    end

    sig { returns(String) }
    def runner_group_path
      @larger_runner.runner_group_path(@owner_settings)
    end

    sig { returns(T::Boolean) }
    def runner_in_shutdown_billing?
      @larger_runner.state == :ShutdownBilling
    end

    sig { returns(T::Boolean) }
    def runner_in_shutdown_network?
      @larger_runner.state == :ShutdownNetwork
    end

    sig { returns(T::Boolean) }
    def runner_error_is_vnet_unreachable_internet?
      @larger_runner.error_code == "VNetInjectionFailedToConnectToInternet"
    end

    sig { returns(T::Boolean) }
    def runner_error_is_vnet_deployment_blocked_by_policy?
      @larger_runner.error_code == "RunnerDeploymentBlockedByPolicy"
    end

    sig { returns(T::Boolean) }
    def runner_error_is_vnet_deployment_scope_locked?
      # These errors are very similar, so just show the same error message
      @larger_runner.error_code.in?(%w[RunnerDeploymentScopeLocked RunnerDeploymentScopeLockedCreateOnly])
    end

    sig { returns(T::Boolean) }
    def runner_error_is_subscription_not_found?
      @larger_runner.error_code == "SubscriptionNotFound"
    end

    sig { returns(T::Boolean) }
    def runner_error_is_vnet_subnet_full?
      @larger_runner.error_code == "VNetInjectionSubnetIsFull"
    end

    sig { returns(T::Boolean) }
    def runner_error_is_vnet_capacity_incompatible?
      @larger_runner.error_code == "VNetInjectionCapacityIncompatible"
    end

    sig { returns(T::Boolean) }
    def runner_error_is_agent_cannot_transition_online?
      @larger_runner.error_code == "AgentCannotTransitionOnline"
    end

    sig { returns(T::Boolean) }
    def vnet_injection_enabled?
      return false if @larger_runner.runner_group_id.nil?

      is_vnet_injection_enabled?(@owner, @larger_runner.runner_group_id)
    end

    sig { returns(T::Boolean) }
    def runner_error_is_agent_cannot_transition_online_custom_image_issue?
      runner_error_is_agent_cannot_transition_online? && runner_image_source_is_custom && !vnet_injection_enabled?
    end

    sig { returns(T::Boolean) }
    def runner_error_is_agent_cannot_transition_online_ambiguous_issue?
      runner_error_is_agent_cannot_transition_online? && runner_image_source_is_custom && vnet_injection_enabled?
    end

    sig { returns(T::Boolean) }
    def runner_error_is_agent_cannot_transition_online_network_connectivity_issue?
      runner_error_is_agent_cannot_transition_online? && !runner_image_source_is_custom && vnet_injection_enabled?
    end

    sig { returns(T::Boolean) }
    def runner_error_is_network_connectivity_issue?
      runner_error_is_vnet_unreachable_internet? || runner_error_is_agent_cannot_transition_online_network_connectivity_issue?
    end

    sig { returns(T::Boolean) }
    def runner_error_is_image_larger_than_disk?
      @larger_runner.error_code == "ImageLargerThanDiskSize"
    end

    sig { returns(T::Boolean) }
    def runner_error_is_custom_image_version_not_found?
      @larger_runner.error_code.in?(%w[CustomImageVersionNotFound CustomImageVersionFailed])
    end

    sig { returns(T::Boolean) }
    def runner_error_is_image_version_disabled?
      @larger_runner.error_code == "ImageVersionDisabled"
    end

    sig { returns(T::Boolean) }
    def runner_error_is_custom_image_definition_not_found?
      @larger_runner.error_code == "CustomImageDefinitionNotFound"
    end

    sig { returns(T::Boolean) }
    def ubuntu_20_deprecation?
      FeatureFlag.vexi.enabled?(:ubuntu_20_deprecation, @owner, default: false) && @larger_runner.image&.id == "2296"
    end

    sig { returns(T::Boolean) }
    def runner_error_is_vnet_deployment_blocked_by_conflicting_policies?
      @larger_runner.error_code == "RunnerDeploymentConflictingPolicies"
    end

    sig { returns(T::Boolean) }
    def should_show_error_banner?
      runner_in_shutdown_network? ||
      runner_in_shutdown_billing? ||
      runner_error_is_vnet_unreachable_internet? ||
      runner_error_is_vnet_deployment_blocked_by_policy? ||
      runner_error_is_vnet_deployment_scope_locked? ||
      runner_error_is_subscription_not_found? ||
      runner_error_is_vnet_subnet_full? ||
      runner_error_is_vnet_capacity_incompatible? ||
      runner_error_is_agent_cannot_transition_online? ||
      runner_error_is_image_larger_than_disk? ||
      ubuntu_20_deprecation? ||
      runner_error_is_custom_image_version_not_found? ||
      runner_error_is_image_version_disabled? ||
      runner_error_is_custom_image_definition_not_found? ||
      runner_error_is_vnet_deployment_blocked_by_conflicting_policies?
    end

    sig { returns(String) }
    def billing_details_link
      return enterprise_billing_budgets_path(@owner.slug) if @owner.is_a?(Business)
      return settings_org_billing_path(@owner_settings.settings_owner.display_login) if @owner_settings.settings_owner.is_a?(Organization)

      settings_user_billing_path
    end

    sig { returns(String) }
    def runner_group_network_configuration_name
      @network_configuration_name
    end

    sig { returns(T::Boolean) }
    def show_image_gen_enabled?
      @image_gen_feature_enabled && @larger_runner.persistent_os_disk
    end

    sig { returns(T::Boolean) }
    def network_configuration_visible?
      can_view_network_configuration?(@owner)
    end

    sig { returns(T::Boolean) }
    def macos_runner?
      @larger_runner.platform&.start_with?("macos-") || false
    end

    sig { returns(T::Boolean) }
    def show_networking_sections?
      !macos_runner?
    end

    sig { returns(T.nilable(T::Hash[String, T.untyped])) }
    def parsed_error_details
      return nil unless @larger_runner.error_details.present?

      GitHub::JSON.parse(@larger_runner.error_details, failsafe: true)
    end
  end
end
