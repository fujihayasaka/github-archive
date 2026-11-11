# typed: true
# frozen_string_literal: true

class Businesses::SecurityCenter::DependabotAlertsController < Businesses::SecurityCenter::AbstractSecurityCenterController
  include Dependabot::AlertDependency

  before_action :check_feature_enabled
  before_action :security_center_required
  before_action :require_malware_frontend_enabled, if: :malware_route?

  skip_before_action :cap_pagination, unless: :robot?

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Iam,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql5,
    only: [:index],
    optional: true

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Iam,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    only: [:filter_input_suggestions]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Iam,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    only: [:menu_content]

  VALID_MENU_CONTENT_OPTIONS = [
    (ORG_FILTER_NAME = "org"),
    (REPO_FILTER_NAME = "repo"),
    (SEVERITY_FILTER_NAME = "severity"),
    (PACKAGE_FILTER_NAME = "package"),
    (ECOSYSTEM_FILTER_NAME = "ecosystem"),
    (RESOLUTION_FILTER_NAME = "resolution"),
  ].freeze

  def index
    es_query_result = T.let(nil, T.nilable(Search::Responses::CursorPaginationResponse))
    read_from_es = GitHub.dependabot_es_search_enabled?

    GitHub.dogstats.distribution_time(
      "dependabot_alerts.index.query_time",
      tags: query.datadog_tags + ["source:ui", "read_from:#{read_from_es ? 'es' : 'db'}"]
    ) do
      if read_from_es
        pagination_params = {}
        if params[:after].present?
          pagination_params = { after: params[:after] }
        elsif params[:before].present?
          pagination_params = { before: params[:before] }
        end

        es_query = Search::Queries::DependabotAlertsEsQuery.new(phrase: es_query_phrase,
          scope: this_business,
          aggregations: true,
          current_user:,
          cap_filter:,
          **pagination_params
        )
        es_query_result = es_query.execute
        prefill_associations_for_ui(es_query_result.models)
      else
        query.alerts
      end
    end

    render "businesses/security_center/dependabot_alerts/index", locals: {
      sso_payload:,
      query: query,
      es_query_result:,
      query_string: query_string,
      alerts_page_path: method(alerts_page_path_name),
      filter_suggestions_path: method(:filter_suggestions_path),
      menu_content_path: method(:menu_content_path),
      teams_filter_menu_data: teams_filter_menu_data,
      use_es: read_from_es,
      save_view_path: "/enterprises/#{this_business.slug}/security/alerts/dependabot/save-view",
      heading: malware_route? ? "Malware alerts" : "Dependabot alerts",
      phase: malware_route? ? :preview : :ga,
    }
  end

  def menu_content # rubocop:todo GitHub/UseRestfulActions
    page_path = method(alerts_page_path_name)
    case params[:menu_content]
    when ORG_FILTER_NAME
      render DependabotAlerts::AlertFilterComponent.new(
        filter_type: ORG_FILTER_NAME,
        query_string: query_string,
        item_list: query.organization_filter_options,
        alerts_page_path: page_path,
      ), layout: false
    when REPO_FILTER_NAME
      render DependabotAlerts::AlertFilterComponent.new(
        filter_type: REPO_FILTER_NAME,
        query_string: query_string,
        item_list: query.repository_filter_options,
        alerts_page_path: page_path,
      ), layout: false
    when SEVERITY_FILTER_NAME
      render DependabotAlerts::AlertFilterV2Component.new(
        filter_type: SEVERITY_FILTER_NAME,
        query_string: query_string,
        item_list: query.severity_filter_options,
        alerts_page_path: page_path,
      ), layout: false
    when PACKAGE_FILTER_NAME
      render DependabotAlerts::AlertFilterItemListComponent.new(
        filter_type: PACKAGE_FILTER_NAME,
        query_string: query_string,
        item_list: query.package_filter_options,
        alerts_page_path: page_path,
      ), layout: false
    when ECOSYSTEM_FILTER_NAME
      render DependabotAlerts::AlertFilterItemListComponent.new(
        filter_type: ECOSYSTEM_FILTER_NAME,
        query_string: query_string,
        item_list: query.ecosystem_filter_options,
        alerts_page_path: page_path,
      ), layout: false
    when RESOLUTION_FILTER_NAME
      render DependabotAlerts::AlertFilterComponent.new(
        filter_type: RESOLUTION_FILTER_NAME,
        query_string: query_string,
        item_list: query.resolution_filter_options,
        show_search_bar: false,
        alerts_page_path: page_path,
      ), layout: false
    else
      head :bad_request
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

  def menu_content_path(**args)
    args = args.merge(malware: true) if malware_route?
    security_center_alerts_dependabot_menu_content_enterprise_path(**args)
  end

  # Provide scope context for logging in DependabotAlertsSavedView concern
  def scope_context
    { business_id: this_business.id }
  end

  sig { override.returns(Symbol) }
  def authorized_orgs_actions
    :view_dependabot_alerts
  end

  sig { returns(RepositoryVulnerabilityAlert::UngroupedAlertQuery) }
  memoize def query
    query_hash = Search::Queries::SecurityCenter::DependabotAlertsQuery.parse_and_normalize(query_string)

    q = RepositoryVulnerabilityAlert::UngroupedAlertQuery.new(
      business: this_business,
      organization_ids: authorized_orgs.pluck(:id),
      user: current_user,
      user_session: user_session,
    ).
      paginate(params[:page]).
      state_is(query_hash[:is]).
      resolutions_are(query_hash[:resolution]).resolutions_are_not(query_hash[:"-resolution"]).
      severities_are(query_hash[:severity]).severities_are_not(query_hash[:"-severity"]).
      organization_names_are(query_hash[:org]).organization_names_are_not(query_hash[:"-org"]).
      repository_names_are(query_hash[:repo]).repository_names_are_not(query_hash[:"-repo"]).
      teams_are(query_hash[:team]).teams_are_not(query_hash[:"-team"]).
      packages_are(query_hash[:package]).packages_are_not(query_hash[:"-package"]).
      ecosystems_are(query_hash[:ecosystem]).ecosystems_are_not(query_hash[:"-ecosystem"]).
      dependency_scopes_are(query_hash[:scope]).negated_dependency_scopes_are(query_hash[:"-scope"]).
      topics_are(query_hash[:topic]).topics_are_not(query_hash[:"-topic"]).
      has_a(query_hash[:has]).has_none(query_hash[:"-has"]).
      search(query_hash[:phrase]).
      sort_by(query_hash[:sort]).
      epss_percentages_are(query_hash[:epss_percentage]).epss_percentages_are_not(query_hash[:"-epss_percentage"])

    if malware_route?
      q.vulnerability_types_are(["malware"])
    else
      q.vulnerability_types_are_not(["malware"])
    end
  end

  def teams_filter_menu_data
    ::SecurityCenter::SelectPanelComponent::Data.new(
      title: "Teams",
      header: "Filter by team",
      options_src: security_center_options_enterprise_path({
        "options-type": "teams",
        qualifier: ::Search::Queries::SecurityCenter::DependabotAlertsQuery::QUALIFIER_TEAM,
        query: query_string,
        multiselect: true,
        query_parameter_key: "q",
      }),
    )
  end

  def filter_suggestions_path(suggestion: nil)
    malware_params = malware_route? ? { malware: true } : {}
    return security_center_options_enterprise_path("options-type": suggestion.pluralize, **malware_params) if %w[team topic].include?(suggestion)
    security_center_alerts_dependabot_filter_input_suggestions_enterprise_path(suggestion: suggestion, **malware_params)
  end

  def suggestions_for_filter(filter_name = "")
    new_query = RepositoryVulnerabilityAlert::UngroupedAlertQuery.new(business: this_business, organization_ids: authorized_orgs.pluck(:id), user: current_user, user_session: user_session)
    new_query = malware_route? ? new_query.vulnerability_types_are(["malware"]) : new_query.vulnerability_types_are_not(["malware"])

    case filter_name
    when ORG_FILTER_NAME
      new_query.organization_filter_options.map { |org| { value: org[:label] } }.compact
    when REPO_FILTER_NAME
      new_query.repositories_list.order(:name).map { |repo| { value: Search::ParsedQuery.encode_value(repo.name_with_display_owner) } }
    when PACKAGE_FILTER_NAME
      new_query.package_filter_options.map { |package| { value: package[:label] } }.compact
    when ECOSYSTEM_FILTER_NAME
      new_query.ecosystem_filter_options.map { |ecosystem| { value: ecosystem[:label] } }.compact
    else
      []
    end
  end

  def check_feature_enabled
    render_404 unless SecurityCenter::SecurityFeatures.dependabot_alerts_enabled_for_instance?
  end

  def require_malware_frontend_enabled
    render_404 unless FeatureFlag.vexi.enabled?("dependabot_allow_malware_frontend", current_user, this_business, default: false)
  end

  def alerts_page_path_name
    malware_route? ? :security_center_alerts_dependabot_malware_enterprise_path : :security_center_alerts_dependabot_enterprise_path
  end
end
