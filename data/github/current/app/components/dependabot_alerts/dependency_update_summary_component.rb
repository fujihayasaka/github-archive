# typed: true
# frozen_string_literal: true

module DependabotAlerts
  class DependencyUpdateSummaryComponent < ApplicationComponent
    def initialize(alert:)
      @alert = alert
    end

    attr_reader :alert

    delegate \
      :package_name,
      :repository,
      :vulnerable_version_range,
      to: :alert

    delegate \
      :pull_request,
      to: :dependency_update,
      allow_nil: true

    delegate \
      :title,
      to: :pull_request,
      allow_nil: true,
      prefix: true

    def show_pull_request?
      dependency_update.present? && # A dependency update exists
        dependency_update.complete? && # The update request completed successfully
        pull_request.present? && # The update has an associated pull request
        !pull_request.merged? # The pull request isn't already merged
    end

    def show_dependency_update_error?
      dependency_update.present? &&
        (
          dependency_update.error? ||
          dependency_update.dependabot_has_timed_out?
        )
    end

    def show_pending_dependency_update?
      dependency_update.present? && dependency_update.requested?
    end

    # Should we show the "Create Dependabot security update" button?
    #   Only if Dependabot supports the manifest!
    def show_create_update_button?
      RepositoryDependencyUpdate.manifest_path_supported?(manifest_path)
    end

    def create_dependency_update_path
      helpers.repository_alert_bot_resolve_path(
        user_id: repository.owner.display_login,
        repository: repository.name,
        number: alert.number,
      )
    end

    def dependency_update_status_path
      helpers.repository_alert_bot_resolve_status_path(
        user_id: repository.owner.display_login,
        repository: repository.name,
        number: alert.number,
      )
    end

    def related_alerts_link
      helpers.link_to(
        helpers.pluralize(related_alerts.size, "Dependabot alert"),
        helpers.repository_alerts_path(
          user_id: repository.owner.display_login,
          repository: repository.name,
          q: "is:open package:#{package_name} manifest:#{manifest_path} has:patch"
        ),
      )
    end

    def manifest_link
      helpers.link_to(
        manifest_path,
        helpers.default_branch_blob_path(
          user_id: repository.owner.display_login,
          repository: repository.name,
          path: manifest_path,
        ),
      )
    end

    def suggested_version
      suggested_fix.target_version
    end

    memoize def dependency_upgrade_examples
      helpers.dependency_upgrade_examples(
          manifest_path: manifest_path,
          package_name: package_name,
          suggested_version: suggested_version,
        )
    end

    def dependency_update_error_title
      return RepositoryDependencyUpdate::TIMEOUT_ERROR_TITLE if dependency_update.dependabot_has_timed_out?

      dependency_update.error_title
    end

    def dependency_update_error_body
      return RepositoryDependencyUpdate::TIMEOUT_ERROR_BODY if dependency_update.dependabot_has_timed_out?

      dependency_update.error_body
    end

    def dependency_update_logs_available?
      return false unless dependency_update
      return false if dependency_update.dependabot_has_timed_out?

      dependency_update.created_at > RepositoryDependencyUpdate::DEPENDABOT_UPDATE_JOB_LOG_RETENTION.ago
    end

    def dependency_update_logs_path
      return unless dependency_update

      helpers.repository_alert_update_logs_path(
        user_id: repository.owner.display_login,
        repository: repository.name,
        number: alert.number,
        dependency_update_id: dependency_update.id,
      )
    end

    def dependency_update_troubleshooting_path
      "#{GitHub.help_url}/github/managing-security-vulnerabilities/troubleshooting-dependabot-errors"
    end

    def pull_request_path
      pull_request && helpers.pull_request_path(pull_request, repository)
    end

    def pull_request_link_data_attributes
      return {} unless pull_request

      {
        hovercard_type: "pull_request",
        hovercard_url: "#{pull_request_path}/hovercard",
      }
    end

    def pull_request_button_scheme
      if pull_request.open? && !pull_request.draft?
        :primary
      else
        :default
      end
    end

    private

    def render?
      alert.open? && # Only show dependency update dialogs if the alert is still open
        alert.vulnerable_version_range.fixed_in? && # Only show dependency update dialogs if the alert is fixable
        security_updates_supported? && # Only show dependency update dialogs if security updates are supported
        repository.automated_security_updates_visible_to?(current_user) # and the user can create security updates
    end

    def security_updates_supported?
      Dependabot.security_updates_supported?(package_ecosystem: vulnerable_version_range.ecosystem)
    end

    def manifest_path
      alert.vulnerable_manifest_path
    end

    memoize def dependency_update
      alert.current_dependency_update
    end

    memoize def suggested_fix
      RepositoryVulnerabilityAlert::SuggestedFix.new(related_alerts)
    end

    memoize def related_alerts
      repository.repository_vulnerability_alerts.
        open.
        for_manifest_and_package(manifest_path: manifest_path, package_name: package_name).
        preload(:vulnerable_version_range). # Used in RepositoryVulnerabilityAlert::SuggestedFix
        select { |a| a.vulnerable_version_range.fixed_in? } # Only consider fixable alerts
    end

    memoize def pull_request_icon
      PullRequest::Icon.new(
        pull_request,
        permit_queued_icon: false, # TODO: Remove this after resolving N+1 issues
      )
    end
  end
end
