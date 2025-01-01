# typed: true
# frozen_string_literal: true

module RepositoryAlerts
  class IndexView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include GitHub::ResilienceMixin
    include GitHub::Memoizer

    attr_reader :query_string, :query, :alerts, :current_repository, :alerts_page_path, :filter_suggestions_path, :menu_content_path

    def open?
      query.open?
    end

    def closed?
      query.closed?
    end

    def state
      open? ? "open" : "closed"
    end

    def open_count
      @open_count ||= query.open.count
    end

    def total_open_count
      @total_open_count ||= query.open_count
    end

    def total_closed_count
      @total_closed_count ||= query.closed_count
    end

    def alerts_enabled?
      return @alerts_enabled if defined? @alerts_enabled
      @alerts_enabled = current_repository.vulnerability_alerts_enabled?
    end

    def display_alerts?
      return @display_alerts if defined? @display_alerts
      @display_alerts = alerts_enabled? && alerts.any?
    end

    def new_to_alerts?
      total_open_count + total_closed_count == 0
    end

    def dismissal_reasons
      RepositoryVulnerabilityAlert::DISMISS_REASONS
    end

    def security_and_analysis_path
      urls.repository_security_and_analysis_path(repository: current_repository, user_id: current_repository.owner)
    end

    def dependabot_rules_path
      urls.dependabot_rules_path(user_id: current_repository.owner, repository: current_repository)
    end

    # Determine if the current user has access to the repository settings tab.
    # User is either an admin or security manager on the repository.
    def show_repository_settings_link?
      SecurityProduct::Permissions::RepoAuthz.new(current_repository, actor: current_user).can_manage_security_products?
    end

    # Check if Dependabot Updates have been paused and hide or display interactive banner
    def paused_banner_hidden?
      with_database_error_fallback(fallback: false) do
        GitHub.kv.get(self.hide_key_for(current_user)).value { false } # rubocop:todo GitHub/DoNotUseGlobalKv
      end
    end

    def hide_key_for(user)
      "user.dependabot_updates_paused_banner_hidden.#{user.id}"
    end

    def show_paused_banner?
      !paused_banner_hidden? && Dependabot::PausedUpdatesBannerComponent.render?(current_repository)
    end
  end
end
