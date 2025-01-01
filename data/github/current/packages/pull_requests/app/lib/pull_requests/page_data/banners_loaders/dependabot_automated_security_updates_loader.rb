# typed: strict
# frozen_string_literal: true

module PullRequests::PageData
  module BannersLoaders
    class DependabotAutomatedSecurityUpdatesLoader
      include GitHub::Memoizer
      include GitHub::ResilienceMixin

      delegate :package_name, :manifest_path, to: :dependency_update

      sig { returns(T::Hash[Symbol, T.any(T::Boolean, T.untyped)]) }
      attr_reader :data

      sig do
        params(
          current_user: T.nilable(User),
          pull_request: PullRequest,
          repository: Repository).returns(T::Hash[Symbol, T.untyped])
      end
      def self.build(current_user:, pull_request:, repository:)
        automated_security_updates = new(current_user:, pull_request:, repository:)
        automated_security_updates.determine_data
        automated_security_updates.data
      end

      sig { params(current_user: T.nilable(User), pull_request: PullRequest, repository: Repository).void }
      def initialize(current_user:, pull_request:, repository:)
        @current_user = current_user
        @pull_request = pull_request
        @repository = repository

        @data = T.let({ render: false }, T::Hash[Symbol, T.untyped])
      end

      sig { void }
      def determine_data
        display = display_automated_security_updates_banner?
        return unless display
        return false_render_return unless alert.present?

        @data[:render] = display
        @data[:alertPresent] = alert.present?
        @data[:packageName] = package_name
        @data[:singleAlert] = !represents_multiple_alerts?
        @data[:securityAlertPath] = security_alert_path
        @data[:severity] = severity
        @data[:showOnboardingPopover] = show_onboarding_popover?
        @data[:onboardingBannerProps] = T.let({}, T::Hash[Symbol, T.any(T::Boolean, String)])
        @data[:onboardingBannerProps][:dismissNoticePath] = dismiss_notice_path
        @data[:onboardingBannerProps][:helpURL] = dependabot_security_updates_help_url
        @data[:onboardingBannerProps][:repoSettingsPath] = repo_settings_path
        @data[:onboardingBannerProps][:showOptOut] = show_opt_out?
      end

      sig { returns(T::Boolean) }
      def display_automated_security_updates_banner?
        return false unless GitHub.dependabot_enabled?
        return false unless @repository.can_view_vulnerability_alerts?(@current_user)
        return false if @repository.vulnerability_updates_grouping_enabled?

        dependency_update.present?
      end

      sig { returns(T.nilable(::RepositoryDependencyUpdate)) }
      def dependency_update
        with_database_error_fallback(fallback: nil) do
          @pull_request.most_recent_vulnerability_dependency_update
        end
      end

      sig { returns(T.nilable(::RepositoryVulnerabilityAlert)) }
      memoize def alert
        return nil unless dependency_update.present?

        RepositoryVulnerabilityAlert.find_by(id: T.must(dependency_update).repository_vulnerability_alert_id)
      end

      sig { void }
      def false_render_return
        @data[:alertPresent] = false
        @data[:packageName] = ""
        @data[:singleAlert] = false
        @data[:securityAlertPath] = ""
        @data[:severity] = ""
        @data[:showOnboardingPopover] = false
        @data[:onboardingBannerProps] = T.let({}, T::Hash[Symbol, T.any(T::Boolean, String)])
        @data[:onboardingBannerProps][:dismissNoticePath] = ""
        @data[:onboardingBannerProps][:helpURL] = dependabot_security_updates_help_url
        @data[:onboardingBannerProps][:repoSettingsPath] = ""
        @data[:onboardingBannerProps][:showOptOut] = show_opt_out?
      end

      # Does this Dependabot update PR represent more than one Dependabot alert?
      sig { returns(T::Boolean) }
      def represents_multiple_alerts?
        represented_alerts_count > 1
      end

      # Returns the number of RepositoryVulnerabilityAlerts this update could be related to.
      sig { returns(Integer) }
      memoize def represented_alerts_count
        return 0 if alert.blank?

        T.must(alert).related_fixable_alerts.count
      end

      sig { returns(String) }
      memoize def severity
        severity = alert&.severity
        severity = alert&.highest_severity_of_related_fixable_alerts if represents_multiple_alerts?

        severity || ""
      end

      sig { returns(String) }
      def security_alert_path
        return multiple_alert_path if represents_multiple_alerts?

        Rails.application.routes.url_helpers.repository_alerts_path(
          user_id: @repository.owner_display_login,
          repository: @repository.name)
      end

      sig { returns(String) }
      def multiple_alert_path
        Rails.application.routes.url_helpers.repository_alerts_path(
          user_id: @repository.owner_display_login,
          repository: @repository.name,
          q: "package:#{package_name} manifest:#{manifest_path} has:patch"
        )
      end

      sig { returns(T::Boolean) }
      def show_onboarding_popover?
        return false unless @current_user

        with_database_error_fallback(fallback: false) do
          !@current_user.dismissed_notice?("automated_security_pull_requests")
        end
      end

      sig { returns(T::Boolean) }
      def show_opt_out?
        SecurityProduct::Permissions::RepoAuthz.new(@repository, actor: @current_user).can_manage_security_products?
      end

      sig { returns(String) }
      def repo_settings_path
        Rails.application.routes.url_helpers.repository_security_and_analysis_path(@repository.owner, @repository)
      end

      sig { returns(String) }
      def dismiss_notice_path
        Rails.application.routes.url_helpers.dismiss_notice_path("automated_security_pull_requests")
      end

      sig { returns(String) }
      def dependabot_security_updates_help_url
        GitHub.dependabot_security_updates_help_url
      end
    end
  end
end
