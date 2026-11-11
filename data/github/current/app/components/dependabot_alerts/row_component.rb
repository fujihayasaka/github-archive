# typed: true
# frozen_string_literal: true

module DependabotAlerts
  class RowComponent < ApplicationComponent
    include IssuesHelper
    include HovercardHelper

    attr_reader :alert, :pull_request, :repository, :scope, :show_repository, :show_alert_number, :query_string, :alerts_page_path, :show_bulk_edit

    DISMISS_ALL_PREFIX = "dismiss all:"
    FIXED_REASON = "fixed"
    AUTO_DISMISSED_REASON = "auto-dismissed"

    def initialize(
      alert:,
      pull_request: nil,
      repository: alert.repository,
      scope:,
      show_alert_number: true,
      query_string: nil,
      alerts_page_path: nil,
      show_bulk_edit: false
    )
      @alert = alert
      @pull_request = pull_request
      @repository = repository
      @scope = scope
      @show_repository = scope != :repository
      @show_alert_number = show_alert_number
      @query_string = query_string
      @alerts_page_path = alerts_page_path
      @show_bulk_edit = show_bulk_edit
    end

    def render?
      alert&.active?
    end

    def show_dev_dependency_label?
      dependency_scope == "development"
    end

    def show_direct_dependency_label?
      return false unless DependencyGraph::VulnerabilityScanning.relationship_information_available?
      dependency_relationship == "direct"
    end

    private

    delegate \
      :created_at,
      :dependency_scope,
      :dependency_relationship,
      :ecosystem,
      :package_name,
      :severity,
      :title,
      to: :alert

    delegate :number, to: :alert, prefix: true

    def manifest_path
      alert.vulnerable_manifest_path
    end

    def manifest_blob_path
      helpers.default_branch_blob_path(
        user_id: repository.owner.display_login,
        repository: repository.name,
        path: manifest_path,
      )
    end

    def state
      alert.alert_state
    end

    def alert_path
      helpers.repository_alert_path(
        user_id: repository.owner.display_login,
        repository: repository.name,
        number: alert.number,
      )
    end

    def hovercard_data_attributes
      hovercard_data_attributes_for_dependabot_alert(repository.owner.display_login, repository.name, alert.number)
    end

    def pull_request_path
      return unless pull_request

      helpers.show_pull_request_path(
        user_id: repository.owner.display_login,
        repository: repository.name,
        id: pull_request.number,
      )
    end

    def pull_request_hovercard_data_attributes
      return {} unless pull_request

      {
        hovercard_type: "pull_request",
        hovercard_url: "#{pull_request_path}/hovercard"
      }.merge(test_selector_hash("alert-row-pull-request-number"))
    end

    def ecosystem_label
      ::AdvisoryDB::Ecosystems.label(ecosystem)
    end

    def alert_state_icon
      return "shield-check" if closed?
      "shield"
    end

    def alert_state_label
      state = closed? ? "closed" : "opened"
      show_alert_number ? state : state.capitalize
    end

    # Returns the timestamp we should render based off of the alert state.
    def alert_state_timestamp
      alert.last_state_change_at || alert.created_at
    end

    def closed?
      alert.dismissed? || alert.fixed? || alert.auto_dismissed?
    end

    def closed_reason
      case alert.state
      when "dismissed"
        if alert.dismiss_reason.present?
          alert.dismiss_reason.downcase.delete_prefix(DISMISS_ALL_PREFIX).strip
        else
          nil
        end
      when "fixed"
        FIXED_REASON
      when "auto_dismissed"
        AUTO_DISMISSED_REASON
      else
        nil
      end
    end

    def filtered_by_resolution_url
      return unless query_string.present?
      return unless closed_reason.present?

      # TEMPORARY: Until we launch this feature, we can't add the auto-dismissed resolution value to
      # RepositoryVulnerabilityAlert::RESOLUTION_OPTIONS, lest it show up where the feature flag isn't enabled,
      # so we need to manually set the slug value here when alerts are auto-dismissed:
      if alert.state == "auto_dismissed"
        slug_value = "auto-dismissed"
      else
        slug_value = Search::Queries::SecurityCenter::DependabotAlertsQuery.map_alert_resolution_to_slug_value(closed_reason)
      end

      new_query_string = Search::Queries::SecurityCenter::DependabotAlertsQuery.toggle_qualifier(
        query_string,
        Search::Queries::SecurityCenter::DependabotAlertsQuery::QUALIFIER_RESOLUTION,
        slug_value
      ).presence
      alerts_page_path&.call(q: new_query_string)
    end

    def severity_label_kwargs
      default_kwargs = { severity: severity, verbose: false }

      if render_label_links?
        href = url_for(q: add_or_replace_query_qualifier(Search::Queries::SecurityCenter::DependabotAlertsQuery::QUALIFIER_SEVERITY, severity))
        default_kwargs.merge({ tag: :a, href: href })
      else
        default_kwargs
      end
    end

    def scope_label_kwargs
      if render_label_links?
        href = url_for(q: add_or_replace_query_qualifier(Search::Queries::SecurityCenter::DependabotAlertsQuery::QUALIFIER_SCOPE, dependency_scope))
        { tag: :a, href: href }
      else
        {}
      end
    end

    def relationship_label_kwargs
      if render_label_links?
        href = url_for(q: add_or_replace_query_qualifier(Search::Queries::SecurityCenter::DependabotAlertsQuery::QUALIFIER_RELATIONSHIP, dependency_relationship))
        { tag: :a, href: href }
      else
        {}
      end
    end

    def display_bulk_edit?
      scope == :organization || @show_bulk_edit
    end

    def disallow_bulk_edit?
      alert.fixed? ||
      (scope == :repository && !@show_bulk_edit) ||
      (scope == :organization && !(alert&.repository&.can_resolve_vulnerability_alerts?(current_user)))
    end

    memoize def render_label_links?
      return false unless query_string.present?

      true
    end

    def add_or_replace_query_qualifier(qualifier, value)
      Search::Queries::SecurityCenter::DependabotAlertsQuery.add_or_replace(query_string, qualifier, value)
    end
  end
end
