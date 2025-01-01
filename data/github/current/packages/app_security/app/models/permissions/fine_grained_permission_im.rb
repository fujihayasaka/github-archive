# typed: true
# frozen_string_literal: true

module Permissions

  class FineGrainedPermissionIm
    extend T::Sig

    TARGET_TYPES = %w(
      Business
      MemexProject
      Organization
      Package
      Repository
      Team
    )

    attr_reader :action, :custom_roles_enabled, :target_type

    def initialize(action, custom_roles_enabled: false, target_type: nil)
      @action = action.to_s # previous active record model returned strings for actions
      @custom_roles_enabled = custom_roles_enabled
      @target_type = target_type
      raise ArgumentError.new("Invalid target type") unless TARGET_TYPES.include?(target_type)
      raise ArgumentError.new("Invalid action") if @action.blank?
    end

    # Load FGPs from system_roles.yml
    def self.system_fgps
      @@fgps ||= GitHub.system_roles_config["fine_grained_permissions"].map do |action, properties|
        FineGrainedPermissionIm.new(action.to_sym, custom_roles_enabled: properties["custom_role_enabled"], target_type: properties["target_type"])
      end
    end

    def self.custom_roles_enabled
      where(custom_roles_enabled: true)
    end

    # Look up custom roles by target type.
    def self.custom_roles_enabled_for(target_type)
      where(custom_roles_enabled: true, target_type: target_type)
    end

    # helper for pulling just enabled enterprise role fgps
    def self.enterprise_fgps_for_custom_roles
      custom_roles_enabled_for("Business")
    end

    # helper for pulling just enabled org role fgps
    def self.org_fgps_for_custom_roles
      custom_roles_enabled_for("Organization")
    end

    # helper for pulling just enabled repo role fgps
    def self.repo_fgps_for_custom_roles
      custom_roles_enabled_for("Repository")
    end

    def self.permissions_for_custom_roles(owner, actions: nil, target_type: nil)
      fgps = where(actions: actions, custom_roles_enabled: true, target_type: target_type)
      disabled_actions = disabled_fgps(owner)
      fgps.reject! { |f| disabled_actions.include?(f.action.to_sym) }
      fgps
    end

    def self.where(actions: nil, custom_roles_enabled: nil, target_type: nil)
      fgps = system_fgps
      if actions
        # preserve the order of the passed actions
        actions = Array.wrap(actions).map(&:to_s).uniq
        fgps = actions.map { |a| system_fgps.find { |f| f.action == a } }.reject { |f| f.nil? }
      end
      fgps = fgps.select { |f| f.custom_roles_enabled == custom_roles_enabled } unless custom_roles_enabled.nil?
      fgps = fgps.select { |f| f.target_type == target_type } unless target_type.nil?
      fgps.map { |f| f.dup } # return copies so the original cannot be modified
    end

    def self.find(action)
      system_fgps.find { |f| f.action == action.to_s }.dup # return a copy so the original cannot be modified
    end

    def self.all
      system_fgps.map { |f| f.dup }
    end

    def self.with_testing_permission(fgps, &block)
      raise NotImplementedError.new("This method is not supported except in test") unless Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv

      fgps = Array.wrap(fgps)
      to_remove = []
      fgps.each do |fgp|
        if fgp.is_a?(FineGrainedPermission)
          raise ArgumentError.new("Instances of FineGrainedPermission are no longer supported, please use Permissions::FineGrainedPermissionIm")
        end

        next if system_fgps.include?(fgp)
        to_remove << fgp
        system_fgps << fgp
      end

      begin
        block.call
      ensure
        to_remove.each do |fgp|
          system_fgps.delete(fgp)
        end
      end
    end

    # Public: returns the input FGPs minus any FGP which is currently disabled.
    # This is a temporary method, to be used during the rollout of the new FGPs.
    # See https://github.com/github/authorization/issues/1321 for more information.
    #
    # - fgps: a Symbol or String Array of FGP names.
    #
    # Returns an Array of symbols
    sig { params(fgps: T.untyped, owner: T.any(Organization, Business)).returns(T::Array[Symbol]) }
    def self.only_enabled_fgps(fgps, owner)
      fgps.map(&:to_sym) - disabled_fgps(owner)
    end

    # Public: the list of new FGPs which are currently disabled.
    # This is a temporary method, to be used during the rollout of the new FGPs.
    # See https://github.com/github/authorization/issues/1321 for more information.
    #
    # Returns an Array of symbols
    sig { params(owner: T.any(Organization, Business)).returns(T::Array[Symbol]) }
    def self.disabled_fgps(owner)
      disabled_fgps = []

      # Pending deletion FGP
      disabled_fgps << :manage_discussion_badges

      # Feature flagged Organization targeted FGPs
      disabled_fgps << :manage_organization_actions_self_hosted_runners unless owner.feature_enabled?(:actions_self_hosted_settings_fgp)

      disabled_fgps << :set_issue_type unless owner.feature_enabled?(:issue_types)

      unless GitHub.merge_queues_enabled?
        disabled_fgps << :jump_merge_queue
        disabled_fgps << :create_solo_merge_queue_entry
      end

      disabled_fgps += action_fgps unless GitHub.actions_enabled?
      disabled_fgps << :manage_organization_oauth_application_policy unless GitHub.oauth_application_policies_enabled?

      # only enabled if interaction limits are enabled
      disabled_fgps << :set_interaction_limits unless GitHub.interaction_limits_enabled?

      # See https://github.com/github/actions-sudo/issues/433
      unless owner.feature_enabled?(:packages_org_write_fgp)
        disabled_fgps << :write_organization_packages
      end

      if owner.is_a?(Organization)
        # only valid for GHEC/GHES, so org&.business must exist.
        disabled_fgps << :edit_repo_announcement_banners unless owner.business&.feature_enabled?(:enterprise_banners_repo_level)

        # API Insights Dashboard, https://github.com/github/api-platform/issues/5943
        disabled_fgps << :view_org_api_insights unless owner.feature_enabled?(:api_insights_org_viewer_fgp)

        # https://github.com/github/actions-fusion/issues/1467
        unless owner.feature_enabled?(:actions_usage_metrics) && owner.insights_enabled?
          disabled_fgps << :read_organization_actions_usage_metrics
        end

        # https://github.com/github/hosted-runners/issues/791
        disabled_fgps << :read_organization_network_configurations unless owner.feature_enabled?(:actions_network_configuration_api)
        disabled_fgps << :write_organization_network_configurations unless owner.feature_enabled?(:actions_network_configuration_api)

        # https://github.com/github/secret-scanning/issues/8576
        disabled_fgps << :org_review_and_manage_secret_scanning_bypass_requests unless owner.feature_enabled?(:display_org_review_manage_ss_bypass_requests_fgp)
      end

      if owner.is_a?(Business) && owner.feature_enabled?(:custom_enterprise_role_feature)
        # only valid for GHEC/GHES, so business must exist.
        disabled_fgps << :edit_repo_announcement_banners unless owner.feature_enabled?(:enterprise_banners_repo_level)

        # https://github.com/github/actions-fusion/issues/1467
        unless owner.feature_enabled?(:actions_usage_metrics) && GitHub.insights_enabled?
          disabled_fgps << :read_organization_actions_usage_metrics
        end

        # https://github.com/github/hosted-runners/issues/791
        disabled_fgps << :read_organization_network_configurations unless owner.feature_enabled?(:actions_network_configuration_api)
        disabled_fgps << :write_organization_network_configurations unless owner.feature_enabled?(:actions_network_configuration_api)
      end

      # these are temporarily disabled for staff-shipping
      disabled_fgps << :manage_topics
      disabled_fgps << :remove_label
      disabled_fgps << :remove_assignee

      disabled_fgps
    end

    sig { returns(T::Array[Symbol]) }
    def self.action_fgps
      [
        :manage_organization_actions_self_hosted_runners,
        :write_organization_runners_and_runner_groups,
        :write_organization_actions_settings,
        :write_organization_actions_secrets,
        :write_organization_actions_variables,
      ]
    end
  end
end
