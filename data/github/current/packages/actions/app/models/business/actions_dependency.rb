# typed: false
# frozen_string_literal: true

# Actions-specific functionality for Businesses
module Business::ActionsDependency
  extend ActiveSupport::Concern

  include ActionsPolicy::AccessPolicyDependency

  def highest_level_allowlist(include_all_allowed: false)
    if include_all_allowed
      return @_highest_level_allowlist_all_allowed if defined?(@_highest_level_allowlist_all_allowed)
      @_highest_level_allowlist_all_allowed = self.async_actions_allowlist.sync
    else
      return @_highest_level_allowlist if defined?(@_highest_level_allowlist)
      allowlist = self.async_actions_allowlist.sync

      # Fix for unexpected data where all_allowed:true and sha_pinning_required:false
      # which is causing the allowlist to be enforced at the wrong level
      allowlist = nil if allowlist&.all_allowed?

      @_highest_level_allowlist = allowlist
    end
  end

  def lowest_level_allowlist
    @_lowest_level_allowlist ||= async_actions_allowlist.sync
  end

  def closest_owner_allowlist
    nil
  end

  # We want to split this token into create and delete in the future
  def runner_creation_token_scope
    runner_registration_token_scope
  end

  def runner_deletion_token_scope
    runner_registration_token_scope
  end

  def can_use_actions_allowlist?
    true
  end

  def to_react_props
    {
      allowsAllActionsAndWorkflows: allows_all_actions?,
      actionsDisabledByOwner: actions_disabled_by_owner?,
      actionsEnabledForAllEntities: actions_enabled_for_all_entities?,
      actionsEnabledForSelectedEntities: actions_enabled_for_selected_entities?,
      actionsDisabled: actions_disabled?,
      allowsGithubOwnedActions: allows_github_owned_actions?,
      allowsVerifiedActions: allows_verified_actions?,
      # Copied from app/forms/actions/policy/selected_actions_options_form.rb function dotcom_connection_required?
      dotcomConnectionRequired: GitHub.dotcom_connection_enabled? && (!(GitHub::Connect.dotcom_connection.check_status == :connected) || !GitHub.dotcom_download_actions_archive_enabled?),
      patterns: (actions_allowlist&.allowed_action_patterns || []).map(&:value).sort,
      highestLevelAllowlist: {
        allowsGithubOwnedActions: highest_level_allowlist&.github_owned_allowed?,
        allowsVerifiedActions: highest_level_allowlist&.verified_allowed?,
        # TODO: Come back to this - do we want to default to empty list here? We lose the null meaning if we do it this way
        patterns: (highest_level_allowlist&.allowed_action_patterns || []).map(&:value).sort,
        specifiedActions: highest_level_specified_actions?
      },
    }
  end

  private

  def runner_registration_token_scope
    "CreateBusinessActionsRunner:#{id}"
  end

  # Initializing Workflow permissions/policies on the Business
  def initialize_workflow_permissions
    return unless FeatureFlag.vexi.enabled_or_raise?(:actions_default_workflow_permissions_new_repos) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage

    set_actions_workflow_permission_can_approve_pr(false, actor)
    set_default_workflow_permissions("read", actor)
  end
end
