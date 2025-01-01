# typed: true
# frozen_string_literal: true

module WorkspaceEditor::User::Dependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { User }

  sig { params(repository: T.nilable(Repository)).returns(T::Boolean) }
  def workspace_editor_preview_enabled?(repository: nil)
    T.bind(self, ::User)
    # Must have editor feature preview on
    return false unless self.feature_preview_enabled?(:copilot_hadron_editor)

    # If force access is enabled, the user has access & bypasses all other checks
    return true if self.feature_enabled?(:hadron_force_access)

    # Must have a repository to check code review access
    return false if repository.nil?

    # we allow users to have copilot access through copilot code review or have appropriate GHAS access

    # GHAS is enabled by default for all public repositories. We only want to give access when a business is paying.
    return true if repository.business && CodeScanning::AutofixCodeql.allowed_by_business?(repository.business) && !repository.public?

    WorkspaceEditor::Access.new(actor: owner, current_repository: repository).has_workspace_editor_preview_access?
  end

  # This is for Next's Copilot Workspace where we are now skipping the waitlist
  # Normally this would belong in its own `workspace` package but this shouldn't need to exist for long
  # This should be cleaned up when it is no longer used in a couple months
  sig { returns(T::Boolean) }
  def copilot_workspace_can_grant_auto_access?
    T.bind(self, ::User)

    log_data = { "at" => "copilot_workspace_can_grant_auto_access", "gh.user.id" => id }

    # Skip waitlist flag must be enabled
    unless feature_enabled?(:copilot_workspace_skip_waitlist)
      GitHub.logger.info("Copilot Workspace Auto Access Denied: Skip waitlist feature flag is not enabled", log_data)
      return false
    end

    # These are two different helper classes that are used to check if a user has access to copilot
    # The preferred one is the Copilot::Public::User but sometimes we need the old one
    copilot_user = Copilot::User.new(self)
    public_copilot_user = Copilot::Public::User.new(self)

    # If user already has access, we don't have to grant it to them
    if copilot_user.workspace_enabled?
      GitHub.logger.info("Copilot Workspace Auto Access Denied: User already has access", log_data)
      return false
    end

    if is_enterprise_managed?
      copilot_business = Copilot::Business.new(enterprise_managed_business)

      if !copilot_business.workspace_for_emu_enabled?
        GitHub.logger.info("Copilot Workspace Auto Access Denied: User is enterprise managed and enterprise policy does not permit access", log_data)
        return false
      end
    end

    # If user is spammy, they are not eligible
    if spammy?
      GitHub.logger.info("Copilot Workspace Auto Access Denied: User is spammy", log_data)
      return false
    end

    # If user has trade restrictions, they are not eligible
    if has_any_trade_restrictions?
      GitHub.logger.info("Copilot Workspace Auto Access Denied: User has trade restrictions", log_data)
      return false
    end

    # Checks if the users' orgs all have beta features enabled
    unless copilot_user.beta_features_github_chat_enabled?
      GitHub.logger.info("Copilot Workspace Auto Access Denied: Not all of User's orgs have beta features enabled", log_data)
      return false
    end

    # Checks if the users' orgs all have extensions enabled
    unless public_copilot_user.extensions_enabled?
      GitHub.logger.info("Copilot Workspace Auto Access Denied: Not all of User's orgs have extensions enabled", log_data)
      return false
    end

    # Does not include freemium users, includes paid users and Stars, MS MVP, Educational (students and teachers),
    # and all of the other complimentary Copilot Pro users
    has_paid_or_complimentary_access = public_copilot_user.has_paid_access? || public_copilot_user.has_free_pro_access?

    # User must have a copilot license
    unless has_paid_or_complimentary_access
      GitHub.logger.info("Copilot Workspace Auto Access Denied: User does not have a copilot license", log_data)
      return false
    end

    GitHub.logger.info("Copilot Workspace Auto Access Granted", log_data)
    true
  end

end
