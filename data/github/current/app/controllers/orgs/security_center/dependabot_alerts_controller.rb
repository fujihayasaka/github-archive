# typed: true
# frozen_string_literal: true

class Orgs::SecurityCenter::DependabotAlertsController < Orgs::SecurityCenter::AbstractSecurityCenterController
  include PackageDependenciesHelper
  include Dependabot::AlertDependency

  # Access checks
  before_action :organization_read_required
  before_action :feature_required
  before_action :security_center_required

  # Background process
  after_action :ensure_security_overview_analytics_reconciliation, only: [:index]
  after_action :trigger_security_overview_analytics_backfill, only: [:index]

  before_action :initialize_query, only: [:index, :closed_as_filter, :repository_filter, :severity_filter, :package_filter, :ecosystem_filter, :dismiss, :reopen]

  # Allow users to view all pages
  skip_before_action :cap_pagination, unless: :robot?

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::ArtifactRegistry,
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
    ApplicationRecord::Copilot,
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
    only: [:closed_as_filter, :ecosystem_filter, :package_filter, :repository_filter, :severity_filter]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::ArtifactRegistry,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    ApplicationRecord::Iam,
    ApplicationRecord::Collab,
    only: [:filter_input_suggestions]

  PROPS_FILTER_NAME = /\Aprops\./
  TEAM_FILTER_NAME = "team"
  TOPIC_FILTER_NAME = "topic"

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
        dismissal_reasons: RepositoryVulnerabilityAlert::DISMISS_REASONS,
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

  def dismiss # rubocop:disable GitHub/UseRestfulActions
    ids = params.require(:ids)
    reason = params.require(:reason)
    comment = normalize_comment(params["alert-dismissal-comment"])

    # Note: this log is temporary for analyzing user behavior of the multi-select after launch...
    # we want to know both why users typically use multi-select (is this use-case addressable with auto-triage rules?)
    # and whether they are dismissing just a few, or the max of all alerts on the page (25)
    # TODO: this log line should be removed a few months after July 2025
    logger.info "#{ids.length} alerts were attempted to be dismissed by User #{current_user.id} for Org #{this_organization.id} with reason: #{reason.inspect} and comment: #{comment.inspect}"

    if comment && (comment.length > STATE_CHANGE_COMMENT_MAX_LENGTH)
      head :bad_request
      return
    end

    scoped_repo_ids = if can_view_all_alerts?
      this_organization.repositories.pluck(:id)
    else
      this_organization.repositories.where(id: allowed_repository_ids_for_organization_members).pluck(:id)
    end

    selected_rvas = RepositoryVulnerabilityAlert.open.where(id: ids, repository_id: scoped_repo_ids)

    alerts_count = 0
    selected_rvas.find_each do |alert|
      alert.dismiss(actor: current_user, reason: reason, comment: comment)
      alerts_count += 1
    end
    redirect_to security_center_alerts_dependabot_path(org: this_organization), notice: "Successfully dismissed #{alerts_count} #{"alert".pluralize(alerts_count)}."
  end

  def reopen # rubocop:disable GitHub/UseRestfulActions
    ids = params.require(:ids)

    # Note: this log is temporary for analyzing user behavior of the multi-select after launch...
    # we want to know whether they are re-opening just a few, or the max of all alerts on the page (25)
    # TODO: this log line should be removed a few months after July 2025
    logger.info "#{ids.length} alerts were attempted to be reopened by User #{current_user.id} for Org #{this_organization.id}"

    scoped_repo_ids = if can_view_all_alerts?
      this_organization.repositories.pluck(:id)
    else
      this_organization.repositories.where(id: allowed_repository_ids_for_organization_members).pluck(:id)
    end

    selected_rvas = RepositoryVulnerabilityAlert.reopenable.where(id: ids, repository_id: scoped_repo_ids)

    alerts_count = 0
    selected_rvas.find_each do |alert|
      alert.reopen(actor: current_user)
      alerts_count += 1
    end

    redirect_to security_center_alerts_dependabot_path(org: this_organization), notice: "Successfully reopened #{alerts_count} #{"alert".pluralize(alerts_count)}."
  end

  private

  def filter_suggestions_path(suggestion:)
    case suggestion
    when PROPS_FILTER_NAME
      prop_name = suggestion.split(".", 2).last
      security_center_options_path("options-type": "props", "name": prop_name)
    when TEAM_FILTER_NAME
      security_center_options_path("options-type": "teams")
    when TOPIC_FILTER_NAME
      security_center_options_path("options-type": "topics")
    else
      security_center_alerts_dependabot_filter_input_suggestions_path(suggestion: suggestion)
    end
  end

  def feature_required
    render_404 unless SecurityCenter::SecurityFeatures.dependabot_alerts_enabled_for_instance?
  end

  def teams_filter_menu_data
    ::SecurityCenter::SelectPanelComponent::Data.new(
      title: "Teams",
      header: "Filter by team",
      options_src: security_center_options_path({
        "options-type": "teams",
        qualifier: ::Search::Queries::SecurityCenter::DependabotAlertsQuery::QUALIFIER_TEAM,
        query: @query_string,
        multiselect: true,
        query_parameter_key: "q",
      }),
    )
  end

  def allowed_repository_ids_for_organization_members
    allowed_repository_ids_by_feature_for_organization_members[SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS]
  end

  def initialize_query
    @query_string = params[:q].kind_of?(String) ? params[:q].strip : Search::Queries::SecurityCenter::DependabotAlertsQuery::DEFAULT_QUERY
    query_hash = Search::Queries::SecurityCenter::DependabotAlertsQuery.parse_and_normalize(@query_string,
      can_sort_by_most_important: !this_organization.feature_flag_enabled?(:dependabot_alerts_restrict_most_important_sort, default: false),
      ignore_sort: this_organization.feature_flag_enabled?(:dependabot_alerts_hide_org_sort, default: false)
    )
    allowed_repo_ids, _ = allowed_repository_ids_for_organization_members unless can_view_all_alerts?

    default_sort_option =
      if this_organization.feature_flag_enabled?(:dependabot_alerts_hide_org_sort, default: false)
        :security_center_statuses_repo_id_asc
      elsif this_organization.feature_flag_enabled?(:dependabot_alerts_restrict_most_important_sort, default: false)
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
      sort_by(query_hash[:sort]).
      epss_percentages_are(query_hash[:epss_percentage]).epss_percentages_are_not(query_hash[:"-epss_percentage"]).
      artifact_registry_urls_are(query_hash[:"artifact-registry-url"]).artifact_registry_urls_are_not(query_hash[:"-artifact-registry-url"]).
      artifact_registries_are(query_hash[:"artifact-registry"])
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
    when ARTIFACT_REGISTRY_URL_FILTER_NAME
      new_query.artifact_registry_url_filter_options.map { |url| { value: url[:label] } }.compact
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
