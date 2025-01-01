# typed: true
# frozen_string_literal: true

class Orgs::SecurityCenter::DependabotAlertsController < Orgs::SecurityCenter::AbstractSecurityCenterController
  include PackageDependenciesHelper

  # Access checks
  before_action :organization_read_required
  before_action :feature_required
  before_action :security_center_required

  # Background process
  after_action :ensure_security_overview_analytics_reconciliation, only: [:index]
  after_action :trigger_security_overview_analytics_backfill, only: [:index]

  before_action :initialize_query, only: [:index, :closed_as_filter, :repository_filter, :severity_filter, :package_filter, :ecosystem_filter]

  # Allow users to view all pages
  skip_before_action :cap_pagination, unless: :robot?

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Notify,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Iam,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters \
    ApplicationRecord::Mysql5,
    ApplicationRecord::SecurityOverviewAnalytics,
    only: [:index],
    optional: true

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    ApplicationRecord::Iam,
    only: [:closed_as_filter]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Notify,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Iam,
    only: [:ecosystem_filter]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Notify,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Iam,
    only: [:package_filter]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Iam,
    only: [:repository_filter]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Notify,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Iam,
    only: [:severity_filter]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    ApplicationRecord::Iam,
    ApplicationRecord::Collab,
    only: [:filter_input_suggestions]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  preload_features [
    :dependency_graph_dgp_backed_npm_alerts
  ], only: [:index]

  REPO_FILTER_NAME = "repo"
  SEVERITY_FILTER_NAME = "severity"
  PACKAGE_FILTER_NAME = "package"
  ECOSYSTEM_FILTER_NAME = "ecosystem"
  RESOLUTION_FILTER_NAME = "resolution"
  CVE_ID_FILTER_NAME = "cve_id"
  GHSA_ID_FILTER_NAME = "ghsa_id"

  def index
    backfill_triggered = this_organization.trigger_security_center_reconciliation

    # Track the time it takes to load the queried alerts, complete with
    # preloaded associations. The result of this method call is memoized.
    GitHub.dogstats.distribution_time(
      "dependabot_alerts.index.query_time",
      tags: @query.datadog_tags
    ) do
      @query.alerts
    end

    GitHub.dogstats.distribution_time(
      "dependabot_alerts.index.render_time",
      tags: @query.datadog_tags
    ) do
      # For regular org members with partial repo access, we need to show a warning if they've exceeded the max number of repos we show.
      _, repo_limit_exceeded = allowed_repository_ids_for_organization_members unless can_view_all_alerts?

      render "orgs/security_center/alerts_dependabot", locals: {
        backfill_in_progress: backfill_triggered,
        organization: this_organization,
        query: @query,
        query_string: @query_string,
        alerts_page_path: method(:security_center_alerts_dependabot_path),
        filter_suggestions_path: method(:filter_suggestions_path),
        menu_content_path: method(:menu_content_path),
        show_incomplete_data_warning: repo_limit_exceeded,
        teams_filter_menu_data: teams_filter_menu_data,
      }
    end
  end

  def closed_as_filter # rubocop:todo GitHub/UseRestfulActions
    render DependabotAlerts::AlertFilterComponent.new(
      alerts_page_path: method(:security_center_alerts_dependabot_path),
      filter_type: RESOLUTION_FILTER_NAME,
      query_string: @query_string,
      item_list: @query.resolution_filter_options,
      show_search_bar: false,
    ), layout: false
  end

  def repository_filter # rubocop:todo GitHub/UseRestfulActions
    render DependabotAlerts::AlertFilterComponent.new(
      alerts_page_path: method(:security_center_alerts_dependabot_path),
      filter_type: REPO_FILTER_NAME,
      query_string: @query_string,
      item_list: @query.repository_filter_options,
    ), layout: false
  end

  def severity_filter # rubocop:todo GitHub/UseRestfulActions
    render DependabotAlerts::AlertFilterV2Component.new(
      alerts_page_path: method(:security_center_alerts_dependabot_path),
      filter_type: SEVERITY_FILTER_NAME,
      query_string: @query_string,
      item_list: @query.severity_filter_options,
    ), layout: false
  end

  def package_filter # rubocop:todo GitHub/UseRestfulActions
    render DependabotAlerts::AlertFilterComponent.new(
      alerts_page_path: method(:security_center_alerts_dependabot_path),
      filter_type: PACKAGE_FILTER_NAME,
      query_string: @query_string,
      item_list: @query.package_filter_options,
    ), layout: false
  end

  def ecosystem_filter # rubocop:todo GitHub/UseRestfulActions
    render DependabotAlerts::AlertFilterComponent.new(
      alerts_page_path: method(:security_center_alerts_dependabot_path),
      filter_type: ECOSYSTEM_FILTER_NAME,
      query_string: @query_string,
      item_list: @query.ecosystem_filter_options,
    ), layout: false
  end

  def menu_content_path(path_args) # rubocop:todo GitHub/UseRestfulActions
    case path_args[:menu_content]
    when REPO_FILTER_NAME
      security_center_alerts_dependabot_repository_filter_path(path_args)
    when SEVERITY_FILTER_NAME
      security_center_alerts_dependabot_severity_filter_path(path_args)
    when PACKAGE_FILTER_NAME
      security_center_alerts_dependabot_package_filter_path(path_args)
    when ECOSYSTEM_FILTER_NAME
      security_center_alerts_dependabot_ecosystem_filter_path(path_args)
    when RESOLUTION_FILTER_NAME
      security_center_alerts_dependabot_closed_as_filter_path(path_args)
    else
      raise ArgumentError, "Unknown menu_content: #{path_args[:menu_content]}"
    end
  end

  def filter_input_suggestions # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.json do
        render json: suggestions_for_filter(params[:suggestion]) || []
      end
    end
  end

  private

  def filter_suggestions_path(suggestion:)
    if suggestion.start_with?("props.")
      prop_name = suggestion.split(".", 2).last
      security_center_options_path("options-type": "props", "name": prop_name)
    elsif %w[team topic].include?(suggestion)
      security_center_options_path("options-type": suggestion.pluralize)
    else
      security_center_alerts_dependabot_filter_input_suggestions_path(suggestion: suggestion)
    end
  end

  def feature_required
    render_404 unless SecurityCenter::SecurityFeatures.dependabot_alerts_enabled_for_instance?
  end

  def teams_filter_menu_data
    return if this_organization.teams.size > TEAM_DROPDOWN_THRESHOLD

    qualifier = ::Search::Queries::SecurityCenter::DependabotAlertsQuery::QUALIFIER_TEAM
    include_clear = ::Search::Queries::SecurityCenter::DependabotAlertsQuery.qualifier_exists?(@query_string, qualifier)
    clear_href = "?q=#{Search::Queries::SecurityCenter::DependabotAlertsQuery.remove_qualifiers(@query_string, [qualifier])}"

    ::SecurityCenter::Coverage::SelectMenuComponent::Data.new(
      name: "Teams",
      header: "Filter by team",
      filter: ::SecurityCenter::Coverage::SelectMenuComponent::Filter.new(placeholder: "Filter teams"),
      options_src: security_center_options_path(
        "options-type": "teams",
        qualifier: qualifier,
        query: @query_string,
        multiselect: true,
        query_parameter_key: "q",
      ),
      clear_option: (::SecurityCenter::Coverage::SelectMenuComponent::ClearOption.new(
        text: "Clear teams",
        href: clear_href,
      ) if include_clear),
    )
  end

  def allowed_repository_ids_for_organization_members
    allowed_repository_ids_by_feature_for_organization_members[SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS]
  end

  def initialize_query
    @query_string = params[:q].kind_of?(String) ? params[:q].strip : Search::Queries::SecurityCenter::DependabotAlertsQuery::DEFAULT_QUERY
    query_hash = Search::Queries::SecurityCenter::DependabotAlertsQuery.parse_and_normalize(@query_string,
      can_sort_by_most_important: !this_organization.feature_enabled?(:dependabot_alerts_restrict_most_important_sort),
      ignore_sort: this_organization.feature_enabled?(:dependabot_alerts_hide_org_sort)
    )
    allowed_repo_ids, _ = allowed_repository_ids_for_organization_members unless can_view_all_alerts?

    default_sort_option =
      if this_organization.feature_enabled?(:dependabot_alerts_hide_org_sort)
        :security_center_statuses_repo_id_asc
      elsif this_organization.feature_enabled?(:dependabot_alerts_restrict_most_important_sort)
        :created_desc
      else
        :most_important
      end

    @query = RepositoryVulnerabilityAlert::UngroupedAlertQuery.
      new(
        organization: this_organization,
        user: current_user,
        user_session: user_session,
        allowed_repository_ids: allowed_repo_ids,
        sort: default_sort_option,
      ).
      paginate(params[:page]).
      state_is(query_hash[:is]).
      resolutions_are(query_hash[:resolution]).resolutions_are_not(query_hash[:"-resolution"]).
      severities_are(query_hash[:severity]).severities_are_not(query_hash[:"-severity"]).
      repository_names_are(query_hash[:repo]).repository_names_are_not(query_hash[:"-repo"]).
      packages_are(query_hash[:package]).packages_are_not(query_hash[:"-package"]).
      ecosystems_are(query_hash[:ecosystem]).ecosystems_are_not(query_hash[:"-ecosystem"]).
      dependency_scopes_are(query_hash[:scope]).negated_dependency_scopes_are(query_hash[:"-scope"]).
      dependency_relationships_are(query_hash[:relationship]).negated_dependency_relationships_are(query_hash[:"-relationship"]).
      teams_are(query_hash[:team]).teams_are_not(query_hash[:"-team"]).
      topics_are(query_hash[:topic]).topics_are_not(query_hash[:"-topic"]).
      custom_properties_are(Search::Queries::SecurityCenter::DependabotAlertsQuery.custom_properties_string(query_hash)).
      has_a(query_hash[:has]).has_none(query_hash[:"-has"]).
      search(query_hash[:phrase]).
      sort_by(query_hash[:sort])
  end

  def suggestions_for_filter(filter_name = "")
    allowed_repo_ids, _ = allowed_repository_ids_for_organization_members unless can_view_all_alerts?
    new_query = RepositoryVulnerabilityAlert::UngroupedAlertQuery.new(organization: this_organization, user: current_user, user_session: user_session, allowed_repository_ids: allowed_repo_ids)

    case filter_name
    when REPO_FILTER_NAME
      new_query.repositories_list.order(:name).map { |repo| { value: Search::ParsedQuery.encode_value(repo.name) } }
    when PACKAGE_FILTER_NAME
      new_query.package_filter_options.map { |package| { value: package[:label] } }.compact
    when ECOSYSTEM_FILTER_NAME
      new_query.ecosystem_filter_options.map { |ecosystem| { value: ecosystem[:label] } }.compact
    when CVE_ID_FILTER_NAME
      new_query.cve_id_filter_options.map { |cve| { value: cve } }.compact
    when GHSA_ID_FILTER_NAME
      new_query.ghsa_id_filter_options.map { |ghsa| { value: ghsa } }.compact
    else
      []
    end
  end

  def table_alerts_count
    if @query.open?
      @query.open_count
    elsif @query.closed?
      @query.closed_count
    else
      @query.open_count + @query.closed_count
    end
  end

  sig { returns(Search::Queries::SecurityCenter::DependabotAlertsQuery) }
  memoize def parsed_query
    Search::Queries::SecurityCenter::DependabotAlertsQuery.new(query: @query_string)
  end
end
