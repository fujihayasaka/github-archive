# typed: true
# frozen_string_literal: true

class Businesses::SecurityCenter::DependabotAlertsController < Businesses::SecurityCenter::AbstractSecurityCenterController
  extend T::Sig

  before_action :check_feature_enabled
  before_action :security_center_required

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
    render "businesses/security_center/dependabot_alerts/index", locals: {
      cap_filter: cap_filter,
      unauthorized_orgs: unauthorized_orgs,
      query: query,
      query_string: query_string,
      alerts_page_path: method(:security_center_alerts_dependabot_enterprise_path),
      filter_suggestions_path: method(:filter_suggestions_path),
      menu_content_path: method(:security_center_alerts_dependabot_menu_content_enterprise_path),
      teams_filter_menu_data: teams_filter_menu_data,
    }
  end

  def menu_content # rubocop:todo GitHub/UseRestfulActions
    case params[:menu_content]
    when ORG_FILTER_NAME
      render DependabotAlerts::AlertFilterComponent.new(
        filter_type: ORG_FILTER_NAME,
        query_string: query_string,
        item_list: query.organization_filter_options,
        alerts_page_path: method(:security_center_alerts_dependabot_enterprise_path),
      ), layout: false
    when REPO_FILTER_NAME
      render DependabotAlerts::AlertFilterComponent.new(
        filter_type: REPO_FILTER_NAME,
        query_string: query_string,
        item_list: query.repository_filter_options,
        alerts_page_path: method(:security_center_alerts_dependabot_enterprise_path),
      ), layout: false
    when SEVERITY_FILTER_NAME
      render DependabotAlerts::AlertFilterV2Component.new(
        filter_type: SEVERITY_FILTER_NAME,
        query_string: query_string,
        item_list: query.severity_filter_options,
        alerts_page_path: method(:security_center_alerts_dependabot_enterprise_path),
      ), layout: false
    when PACKAGE_FILTER_NAME
      render DependabotAlerts::AlertFilterComponent.new(
        filter_type: PACKAGE_FILTER_NAME,
        query_string: query_string,
        item_list: query.package_filter_options,
        alerts_page_path: method(:security_center_alerts_dependabot_enterprise_path),
      ), layout: false
    when ECOSYSTEM_FILTER_NAME
      render DependabotAlerts::AlertFilterComponent.new(
        filter_type: ECOSYSTEM_FILTER_NAME,
        query_string: query_string,
        item_list: query.ecosystem_filter_options,
        alerts_page_path: method(:security_center_alerts_dependabot_enterprise_path),
      ), layout: false
    when RESOLUTION_FILTER_NAME
      render DependabotAlerts::AlertFilterComponent.new(
        filter_type: RESOLUTION_FILTER_NAME,
        query_string: query_string,
        item_list: query.resolution_filter_options,
        show_search_bar: false,
        alerts_page_path: method(:security_center_alerts_dependabot_enterprise_path),
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

  sig { returns(String) }
  memoize def query_string
    params[:q].kind_of?(String) ? params[:q].strip : Search::Queries::SecurityCenter::DependabotAlertsQuery::DEFAULT_QUERY
  end

  sig { returns(RepositoryVulnerabilityAlert::UngroupedAlertQuery) }
  memoize def query
    query_hash = Search::Queries::SecurityCenter::DependabotAlertsQuery.parse_and_normalize(query_string)

    RepositoryVulnerabilityAlert::UngroupedAlertQuery.new(
      business: this_business,
      organization_ids: authorized_org_ids,
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
      sort_by(query_hash[:sort])
  end

  def teams_filter_menu_data
    return if Team.owned_by(authorized_orgs).size > TEAM_DROPDOWN_THRESHOLD

    qualifier = ::Search::Queries::SecurityCenter::DependabotAlertsQuery::QUALIFIER_TEAM
    include_clear = ::Search::Queries::SecurityCenter::DependabotAlertsQuery.qualifier_exists?(query_string, qualifier)
    clear_href = "?q=#{Search::Queries::SecurityCenter::DependabotAlertsQuery.remove_qualifiers(query_string, [qualifier])}"

    ::SecurityCenter::Coverage::SelectMenuComponent::Data.new(
      name: "Teams",
      header: "Filter by team",
      filter: ::SecurityCenter::Coverage::SelectMenuComponent::Filter.new(placeholder: "Filter teams"),
      options_src: security_center_options_enterprise_path(
        "options-type": "teams",
        qualifier: qualifier,
        query: query_string,
        multiselect: true,
        query_parameter_key: "q",
      ),
      clear_option: (::SecurityCenter::Coverage::SelectMenuComponent::ClearOption.new(
        text: "Clear teams",
        href: clear_href,
      ) if include_clear),
    )
  end

  def filter_suggestions_path(suggestion: nil)
    return security_center_options_enterprise_path("options-type": suggestion.pluralize) if %w[team topic].include?(suggestion)
    security_center_alerts_dependabot_filter_input_suggestions_enterprise_path(suggestion: suggestion)
  end

  def suggestions_for_filter(filter_name = "")
    new_query = RepositoryVulnerabilityAlert::UngroupedAlertQuery.new(business: this_business, organization_ids: authorized_org_ids, user: current_user, user_session: user_session)

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
end
