# typed: false
# frozen_string_literal: true

# Actions-specific functionality for organizations
module Organization::ActionsDependency
  extend ActiveSupport::Concern

  include ActionsPolicy::AccessPolicyDependency

  # If an allowlist is defined at a higher level (business) we must respect those settings.
  def highest_level_allowlist(include_all_allowed: false)
    if include_all_allowed
      return @_highest_level_allowlist_all_allowed if defined?(@_highest_level_allowlist_all_allowed)
      allowlist = self.actions_allowlist

      # Inherit from business if available
      return @_highest_level_allowlist_all_allowed = business.highest_level_allowlist(include_all_allowed: true) || allowlist if business.present?
      @_highest_level_allowlist_all_allowed = allowlist
    else
      return @_highest_level_allowlist if defined?(@_highest_level_allowlist)
      allowlist = self.actions_allowlist

      # Fix for unexpected data where all_allowed:true and sha_pinning_required:false
      # which is causing the allowlist to be enforced at the wrong level
      allowlist = nil if allowlist&.all_allowed?

      # Inherit from business if available
      return @_highest_level_allowlist = business.highest_level_allowlist || allowlist if business.present?
      @_highest_level_allowlist = allowlist
    end
  end

  def lowest_level_allowlist
    return @_lowest_level_allowlist if defined?(@_lowest_level_allowlist)
    @_lowest_level_allowlist = actions_allowlist || business&.actions_allowlist
  end

  def closest_owner_allowlist
    business.actions_allowlist if business
  end

  # We want to split this token into create and delete in the future
  def runner_creation_token_scope
    runner_registration_token_scope
  end

  def runner_deletion_token_scope
    runner_registration_token_scope
  end

  def can_use_actions_allowlist?
    GitHub.enterprise? || self.plan.business_plus? || self.plan.enterprise?
  end

  # Initializing Workflow permissions/policies on the Organization
  def initialize_workflow_permissions
    # setting the default Workflow permission
    # for not being able to approve PRs
    # see https://github.com/github/pull-requests/issues/2487 for details
    set_actions_workflow_permission_can_approve_pr(false, actor)

    # skip setting the permissions, so it will be inherited from enterprise
    return if business.present? || associated_business_on_creation.present?

    return unless FeatureFlag.vexi.enabled_or_raise?(:actions_default_workflow_permissions_new_repos) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage

    set_default_workflow_permissions("read", actor)
  end

  # Organizations on the legacy plan cannot use organization variables.
  def can_use_org_variables?
    Billing::ActionsPermission.new(self).status[:error][:reason] != "PLAN_INELIGIBLE" || GitHub.enterprise?
  end

  private

  def runner_registration_token_scope
    "CreateOrgActionsRunner:#{id}"
  end
end
