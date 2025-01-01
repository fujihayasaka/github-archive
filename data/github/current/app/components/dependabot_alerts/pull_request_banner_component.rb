# typed: true
# frozen_string_literal: true

module DependabotAlerts
  class PullRequestBannerComponent < ApplicationComponent
    include ApplicationComponent::Rescuable

    attr_reader :pull_request, :pull_request_state, :repository

    delegate :package_name, :manifest_path, to: :dependency_update

    rescue_from_database_errors with: :nothing

    def initialize(pull_request:, repository:)
      @pull_request = pull_request
      @pull_request_state = pull_request.state
      @repository = repository
    end

    def render?
      return false if repository.vulnerability_updates_grouping_enabled?

      dependency_update.present?
    end

    def dependency_update
      pull_request.most_recent_vulnerability_dependency_update
    end

    memoize def alert
      RepositoryVulnerabilityAlert.find_by(id: dependency_update.repository_vulnerability_alert_id)
    end

    # Should we render the "You can opt out..." message? Only if the user is allowed to change settings.
    #
    # Returns a Boolean
    def show_opt_out?
      SecurityProduct::Permissions::RepoAuthz.new(@repository, actor: current_user).can_manage_repo_security_products?
    end

    def flash_scheme
      if pull_request_state == :merged
        :success
      else
        :default
      end
    end

    # Does this Dependabot update PR represent more than one Dependabot alert?
    #
    # Returns a Boolean
    def represents_multiple_alerts?
      represented_alerts_count > 1
    end

    # Returns the number of RepositoryVulnerabilityAlerts this update could be related to.
    #
    # Returns an Integer
    memoize def represented_alerts_count
      return 0 if alert.blank?

      alert.related_fixable_alerts.count
    end

    memoize def severity
      if represents_multiple_alerts?
        alert.highest_severity_of_related_fixable_alerts
      else
        alert.severity
      end
    end

    def show_onboarding_popover?
      !current_user.dismissed_notice?("automated_security_pull_requests")
    end

    def alert_path
      helpers.repository_alert_path(user_id: repository.owner_display_login, repository: repository.name, number: alert.number)
    end

    def alerts_path
      helpers.repository_alerts_path(user_id: repository.owner_display_login, repository: repository.name)
    end

    def related_alerts_path
      helpers.repository_alerts_path(
        user_id: repository.owner_display_login,
        repository: repository.name,
        q: "package:#{package_name} manifest:#{manifest_path} has:patch"
      )
    end

    def repo_settings_path
      helpers.security_analysis_settings_path(@repository)
    end
  end
end
