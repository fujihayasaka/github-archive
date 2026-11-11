# typed: true
# frozen_string_literal: true

class Integration
  class Permissions
    class Result
      attr_reader :actor, :target, :action, :result, :reason

      def self.for(check, result:, reason: :default)
        new(check.actor, check.target, check.action, result, reason: reason)
      end

      DEFAULT_REASON = "You do not have permission to %{action} this app on %{target}."

      HUMAN_READABLE_REASONS = {
        all_repositories: "You do not have permission to %{action} apps with all repositories on %{target}.",
        requires_org_permissions: "You cannot %{action} apps with organization permissions on %{target}.",
        not_admin_on_subset: "You do not have permission to %{action} this app on these repositories belonging to %{target}.",
        not_owned_by_target: "Repositories must be owned by %{target}.",
        spammy_target: "%{target} has been flagged as spam and therefore cannot install GitHub Apps.",
        spammy_actor: "Your account has been marked as spam and therefore cannot install GitHub Apps on any account.",
        invalid_version: "The requested version of permissions do not belong to this GitHub App.",
        too_many_repositories: "Only #{Integration::InstallationService::DEFAULT_MAX_REPOS} repositories are permitted to be added at a time.",
        suspended: "This app has been blocked by GitHub. Please reach out to support for more details.",
        missing_required_feature_flag: "This feature is not enabled for %{target}.",
        not_admin_on_target: "You must be an admin of %{target} to %{action} this app.",
        requires_enterprise_permissions: "You cannot %{action} apps without enterprise permissions on %{target}.",
        not_owned_by_enterprise: "The app must be owned by the enterprise to %{action} it on %{target}.",
      }.freeze

      def initialize(actor, target, action, result, reason:)
        @actor, @target, @action = actor, target, action
        @result, @reason = result, reason
      end

      def permitted?
        @result
      end

      CONTACT_ORGANIZATION_OWNER_MESSAGE = " Please contact an Organization Owner."

      def error_message
        full_reason = HUMAN_READABLE_REASONS.fetch(reason, DEFAULT_REASON)
        full_reason = full_reason + CONTACT_ORGANIZATION_OWNER_MESSAGE if target.is_a?(Organization)

        I18n.interpolate(full_reason, { action: action, target: target.display_login })
      end
    end
  end
end
