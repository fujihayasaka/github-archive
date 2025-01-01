# typed: strict
# frozen_string_literal: true

module Permissions
  class FineGrainedPermissionIm
    class PermissionNotFoundError < StandardError; end
    class ProgrammaticAccessNotConfiguredError < StandardError; end

    @fgps = T.let(nil, T.nilable(T::Hash[String, FineGrainedPermissionIm]))

    TARGET_TYPES = T.let(%w(
      Business
      Integration
      MemexProject
      Organization
      Package
      Repository
      Team
      CustomCopilot
      Spark::RuntimeApp
    ).to_set.freeze, T::Set[String])

    sig { returns(String) }
    attr_reader :action

    sig { returns(String) }
    attr_reader :target_type

    sig { returns(T::Array[String]) }
    attr_reader :satisfied_by

    sig { returns(T::Boolean) }
    attr_reader :custom_roles_enabled

    sig { returns(T.nilable(Symbol)) }
    attr_reader :category

    sig { returns(T.nilable(String)) }
    attr_reader :description

    sig { returns(T.nilable(Symbol)) }
    attr_reader :feature_flag

    sig { returns(T.nilable(String)) }
    attr_reader :programmatic_action

    sig { returns(T.nilable(String)) }
    attr_reader :programmatic_resource

    sig { returns(T::Array[String]) }
    attr_reader :oauth_scopes

    sig do
      params(
        action: String,
        target_type: String,
        satisfied_by: T::Array[String],
        custom_roles_enabled: T::Boolean,
        category: T.nilable(Symbol),
        description: T.nilable(String),
        feature_flag: T.nilable(Symbol),
        programmatic_action: T.nilable(String),
        programmatic_resource: T.nilable(String),
        oauth_scopes: T::Array[String],
      ).void
    end
    def initialize(action, target_type:, satisfied_by: [], custom_roles_enabled: false, category: nil, description: nil, feature_flag: nil, programmatic_action: nil, programmatic_resource: nil, oauth_scopes: [])
      raise ArgumentError.new("Action can't be blank") if action.blank?
      raise ArgumentError.new("Action can't be none") if action == "none"
      raise ArgumentError.new("Invalid target type") unless TARGET_TYPES.include?(target_type)

      @action = action
      @custom_roles_enabled = custom_roles_enabled
      @target_type = target_type
      @satisfied_by = satisfied_by
      @category = category
      @description = description
      @feature_flag = feature_flag
      @oauth_scopes = oauth_scopes
      @programmatic_action = programmatic_action
      @programmatic_resource = programmatic_resource

      @programmatic_permission_method = T.let(
        case programmatic_action
        when "read"
          "readable_by?"
        when "write"
          "writable_by?"
        when "admin"
          "adminable_by?"
        else
          nil
        end, T.nilable(String))
    end

    sig { returns(T::Boolean) }
    def supports_programmatic_access?
      programmatic_resource.present? && programmatic_permission_method.present?
    end

    sig { returns(T.nilable(String)) }
    private def programmatic_permission_method
      @programmatic_permission_method
    end

    sig { params(subject: T.untyped).returns(T.proc.params(arg0: T.untyped).returns(T.untyped)) }
    def programmatic_access_check_for(subject)
      raise ProgrammaticAccessNotConfiguredError.new("programmatic access is not configured for the '#{action}' FGP") unless supports_programmatic_access?

      proc do |actor|
        # example: repository.resources.contents.readable_by?(actor)
        # See Permissions::FineGrainedResource and sub-classes for metaprogramming implementation details
        subject.resources.send(programmatic_resource).send(programmatic_permission_method, actor) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
      end
    end

    # Load FGPs from system_roles.yml
    sig { returns(T::Hash[String, FineGrainedPermissionIm]) }
    def self.system_fgps
      return @fgps unless @fgps.nil?

      @fgps = GitHub.fine_grained_permissions.each_with_object({}) do |(action, properties), hash|
        hash[action] = FineGrainedPermissionIm.new(
          action,
          custom_roles_enabled: properties["custom_role_enabled"],
          target_type: properties["target_type"],
          satisfied_by: properties["satisfied_by"] || [],
          description: properties["description"],
          category: properties["category"]&.to_sym,
          feature_flag: properties["feature_flag"]&.to_sym,
          programmatic_action: properties["programmatic_action"],
          programmatic_resource: properties["programmatic_resource"],
          oauth_scopes: properties["oauth_scopes"] || []
        ).freeze
      end
    end
    private_class_method :system_fgps

    sig { returns(T::Array[FineGrainedPermissionIm]) }
    def self.all
      system_fgps.values
    end

    sig { returns(T::Array[FineGrainedPermissionIm]) }
    def self.custom_roles_enabled
      where(custom_roles_enabled: true)
    end

    # Look up custom roles by target type.
    sig { params(target_type: String).returns(T::Array[FineGrainedPermissionIm]) }
    def self.custom_roles_enabled_for(target_type)
      where(custom_roles_enabled: true, target_type: target_type)
    end

    # helper for pulling just enabled enterprise role fgps
    sig { returns(T::Array[FineGrainedPermissionIm]) }
    def self.enterprise_fgps_for_custom_roles
      custom_roles_enabled_for("Business")
    end

    # helper for pulling just enabled org role fgps
    sig { returns(T::Array[FineGrainedPermissionIm]) }
    def self.org_fgps_for_custom_roles
      custom_roles_enabled_for("Organization")
    end

    # helper for pulling just enabled repo role fgps
    sig { returns(T::Array[FineGrainedPermissionIm]) }
    def self.repo_fgps_for_custom_roles
      custom_roles_enabled_for("Repository")
    end

    sig { params(owner: T.any(Organization, Business), actions: T.nilable(T::Array[String]), target_type: T.nilable(String)).returns(T::Array[FineGrainedPermissionIm]) }
    def self.permissions_for_custom_roles(owner, actions: nil, target_type: nil)
      fgps = where(actions: actions, custom_roles_enabled: true, target_type: target_type)
      disabled_actions = disabled_fgps(owner, target_type: target_type)
      fgps.reject! { |f| disabled_actions.include?(f.action.to_sym) }
      fgps
    end

    sig { params(actions: T.any(String, Symbol, T::Array[T.any(String, Symbol)], NilClass), custom_roles_enabled: T.nilable(T::Boolean), target_type: T.nilable(String)).returns(T::Array[FineGrainedPermissionIm]) }
    def self.where(actions: nil, custom_roles_enabled: nil, target_type: nil)
      raise ArgumentError.new("Invalid target type") if target_type.present? && !TARGET_TYPES.include?(target_type)

      fgps = if actions
        actions = Array.wrap(actions).map(&:to_s).uniq
        actions.map { |a| system_fgps[a] }.compact
      else
        system_fgps.values.lazy
      end

      fgps = fgps.select { |fgp| fgp.target_type == target_type } unless target_type.nil?
      fgps = fgps.select { |fgp| fgp.custom_roles_enabled == custom_roles_enabled } unless custom_roles_enabled.nil?

      fgps.to_a
    end

    sig { params(action: T.any(Symbol, String)).returns(T.nilable(FineGrainedPermissionIm)) }
    def self.find(action)
      # temporary span to rule this out for authz.domain slowness investigation
      GitHub.tracer.in_span("FineGrainedPermissionsIm.find", kind: :internal) do |_span|
        system_fgps[action.to_s]
      end
    end

    sig { params(action: T.any(Symbol, String)).returns(FineGrainedPermissionIm) }
    def self.find!(action)
      fgp = find(action)
      raise PermissionNotFoundError.new("No permission with the action '#{action}' exists.") unless fgp
      fgp
    end

    sig { params(fgps: T.any(FineGrainedPermissionIm, T::Array[FineGrainedPermissionIm]), block: T.proc.void).returns(T.untyped) }
    def self.with_testing_permission(fgps, &block)
      raise NotImplementedError.new("This method is not supported except in test") unless Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv

      fgps = T.let(Array.wrap(fgps), T::Array[FineGrainedPermissionIm])
      to_remove = []
      fgps.each do |fgp|
        next if system_fgps.key?(fgp.action)
        to_remove << fgp.action
        system_fgps[fgp.action] = fgp
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
    sig { params(fgps: T::Array[T.any(String, Symbol)], owner: T.any(Organization, Business)).returns(T::Array[Symbol]) }
    def self.only_enabled_fgps(fgps, owner)
      fgps.map(&:to_sym) - disabled_fgps(owner)
    end

    # Public: the list of new FGPs which are currently disabled.
    # This is a temporary method, to be used during the rollout of the new FGPs.
    # See https://github.com/github/authorization/issues/1321 for more information.
    # owner: the owner of the FGPs.
    # target_type: the target_type of the FGPs. If not provided, it will be inferred from the owner.
    #
    # Returns an Array of symbols
    sig { params(owner: T.any(Organization, Business), target_type: T.nilable(String)).returns(T::Array[Symbol]) }
    def self.disabled_fgps(owner, target_type: nil)
      target_type ||= owner.is_a?(Business) ? "Business" : "Organization"

      disabled_fgps = []

      system_fgps.select { |_, fgp| fgp.feature_flag.present? }.each do |_, fgp|
        disabled_fgps << fgp.action.to_sym unless owner.feature_enabled?(T.must(fgp.feature_flag))
      end

      # Pending deletion FGP
      disabled_fgps << :manage_discussion_badges

      unless GitHub.merge_queues_enabled?
        disabled_fgps << :jump_merge_queue
        disabled_fgps << :create_solo_merge_queue_entry
      end

      if owner.is_a?(Business)
        disabled_fgps += [:read_enterprise_custom_org_role, :write_enterprise_custom_org_role] unless owner.custom_organization_roles_supported?
        disabled_fgps += [:read_enterprise_custom_enterprise_role, :write_enterprise_custom_enterprise_role] unless owner.custom_enterprise_roles_supported?

        # For non-EMU businesses, disable SCIM permissions
        if !owner.enterprise_managed_user_enabled?
          disabled_fgps << :read_enterprise_scim
          disabled_fgps << :write_enterprise_scim
        end
      end

      disabled_fgps += action_fgps unless GitHub.actions_enabled?
      disabled_fgps << :manage_organization_oauth_application_policy unless GitHub.oauth_application_policies_enabled?

      # only valid for GHEC/GHES, so org&.business must exist.
      unless (owner.is_a?(Organization) && owner.business&.feature_enabled?(:enterprise_banners_repo_level)) || owner.feature_enabled?(:enterprise_banners_repo_level)
        disabled_fgps << :edit_repo_announcement_banners
      end

      # only enabled if interaction limits are enabled
      disabled_fgps << :set_interaction_limits unless GitHub.interaction_limits_enabled?

      # https://github.com/github/actions-fusion/issues/1467
      disabled_fgps << :read_organization_actions_usage_metrics if GitHub.single_or_multi_tenant_enterprise?

      # https://github.com/github/actions-larger-runners/issues/3172
      disabled_fgps << :read_organization_runner_custom_images unless owner.feature_enabled?(:larger_runners_custom_image_generation)
      disabled_fgps << :write_organization_runner_custom_images unless owner.feature_enabled?(:larger_runners_custom_image_generation)

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
        :read_organization_actions_usage_metrics,
      ]
    end
  end
end

# Ensure the permissions are loaded during boot
Permissions::FineGrainedPermissionIm.all
