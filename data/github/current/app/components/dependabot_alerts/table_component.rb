# typed: true
# frozen_string_literal: true

module DependabotAlerts
  class TableComponent < ApplicationComponent
    attr_reader \
      :query,
      :query_string,
      :repository,
      :alerts_page_path,
      :filter_suggestions_path,
      :menu_content_path,
      :show_alert_number,
      :dismissal_reasons,
      :teams_filter_menu_data,
      :show_incomplete_data_warning,
      :organization

    def initialize(
      query:,
      query_string:,
      repository: nil,
      show_alert_number: true,
      alerts_page_path:,
      filter_suggestions_path: nil,
      menu_content_path:,
      dismissal_reasons: {},
      teams_filter_menu_data: nil,
      show_incomplete_data_warning: false,
      organization: nil
    )
      @query = query
      @query_string = query_string
      @repository = repository
      @show_alert_number = show_alert_number
      @alerts_page_path = alerts_page_path
      @filter_suggestions_path = filter_suggestions_path
      @menu_content_path = menu_content_path
      @dismissal_reasons = dismissal_reasons
      @teams_filter_menu_data = teams_filter_menu_data
      @show_incomplete_data_warning = show_incomplete_data_warning
      @organization = organization
    end

    delegate :open_count, :closed_count, to: :query

    def query_string_for_state(str)
      qualifier, value = str.split(":")
      new_query_string = Search::Queries::SecurityCenter::DependabotAlertsQuery.remove_qualifier(query_string, qualifier.to_sym)
      new_query_string = Search::Queries::SecurityCenter::DependabotAlertsQuery.add_or_replace(new_query_string, qualifier.to_sym, value)

      new_query_string
    end

    def dependabot_alerts_state_path(q:)
      alerts_page_path.call(q: query_string_for_state(q))
    end

    memoize def alerts
      alerts = query.alerts

      # When the scope is not repository (rendering in org or business view), the DependabotAlerts::RowComponent
      # doesn't render a link to the pull request, so there's no point in querying for the dependency updates.
      if query.scope == :repository
        GitHub::PrefillAssociations.prefill_batch_method(alerts, :current_dependency_update)
      end

      GitHub::PrefillAssociations.prefill_batch_method(alerts, :current_vulnerable_function_references)

      alerts
    end

    def display_alerts?
      alerts.any?
    end

    def open_selected?
      query.open?
    end

    def closed_selected?
      query.closed?
    end

    def current_path
      url_for(q: nil, only_path: true)
    end

    def filters_applied?
      return true if Search::Queries::SecurityCenter::DependabotAlertsQuery.remove_qualifier(query_string, :is).present?
      return true unless query.valid? # bad/invalid filter gets "no results" experience
      false
    end

    def clear_filters_path
      # If the user's search is invalid, don't try to salvage it. Get back to default state.
      # Just clear all filters and start over. Don't try to salvage any parameters.
      current_path
    end

    def new_to_alerts?
      query.open_count + query.closed_count == 0
    end

    def pull_request_for_alert(alert)
      # When the scope is not repository (rendering in org or business view), the DependabotAlerts::RowComponent
      # doesn't render a link to the pull request, so there's no point in querying for the pull requests.
      return unless query.scope == :repository

      return unless alert.vulnerable_version_range&.fixed_in?
      return unless alert.repository.automated_security_updates_visible_to?(current_user)

      alert.current_dependency_update&.pull_request
    end

    memoize def show_bulk_edit?
      query.scope == :repository &&
        repository&.can_resolve_vulnerability_alerts?(current_user)
    end

    # We should return true here if the alert has function references and if the references are on a public ecosystem.
    # If references are on a preview ecosystem, we should ensure users have access to the preview ecosystem.
    # In all other cases, we should return false
    def has_function_references?(alert)
      return false unless vea_enabled_for_repository?(alert.repository)

      function_references = alert.current_vulnerable_function_references

      function_references.count > 0 &&
        (function_references.first.public_ecosystem? ||
          (GitHub.flipper[:user_can_see_vea_preview_data].enabled?(current_user) && function_references.first.preview_ecosystem?)
        )
    end

    def vea_enabled_for_repository?(repo)
      # VEA is not supported on GitHub Enterprise Server
      !GitHub.enterprise? &&
      repo.vea_on_public_repo_or_advanced_security_enabled?
    end
  end
end
