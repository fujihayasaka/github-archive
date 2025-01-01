# typed: true
# frozen_string_literal: true

class Businesses::SecurityCenter::CodeScanningController < Businesses::SecurityCenter::AbstractSecurityCenterController
  include GitHub::SecurityCenter::TenantFilteringHelper
  include CodeScanningHelper

  before_action :check_feature_enabled
  before_action :security_center_required

  skip_before_action :cap_pagination, unless: :robot?

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Iam,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Notify,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    ApplicationRecord::IssuesPullRequests,
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
    only: [:menu_content]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Iam,
    ApplicationRecord::Repositories,
    ApplicationRecord::Notify,
    ApplicationRecord::Collab,
    only: [:filter_input_suggestions]

  PER_PAGE = DEFAULT_PER_PAGE

  VALID_MENU_CONTENT_OPTIONS = [
    (ORG_FILTER_NAME = "org"),
    (REPO_FILTER_NAME = "repo"),
    (TOOL_FILTER_NAME = "tool"),
    (RULE_FILTER_NAME = "rule"),
    (SEVERITY_FILTER_NAME = "severity"),
  ].freeze

  TAG_FILTER_NAME = "tag"

  def index
    alert_results = []
    open_count = 0
    closed_count = 0
    error_occurred = nil

    if authorized_orgs.any? && query.is_valid?
      # Tenant filtering was performed in alerts_by_repo so the results here are already filtered
      alert_results, _, open_count, closed_count, error_occurred = alert_query_service.alerts_by_repo(
        page: current_page,
        per_page: PER_PAGE
      )
    end

    # Paging
    total_count = query.closed? ? closed_count : open_count # TODO: Is this correct when you don't filter by "is:" at all? (taken from org-level)
    paged_results = WillPaginate::Collection.create(current_page, PER_PAGE, total_count) do |pager|
      pager.replace(alert_results || [])
    end

    alert_number_plus_repository_id_to_assignees = {}
    if this_business.feature_enabled?(:code_scanning_alert_assignment)
      alert_number_plus_repository_id_to_assignees = assignees_by_alert_number_and_repository(paged_results)
    end

    blankslate_text =
      if error_occurred
        Orgs::SecurityCenter::CodeScanningController::BLANKSLATE_ERROR_OCCURRED
      elsif current_page >= 400 # no results after page 399
        Orgs::SecurityCenter::CodeScanningController::BLANKSLATE_TOO_MANY_PAGES
      elsif alert_results.empty?
        Orgs::SecurityCenter::CodeScanningController::BLANKSLATE_NO_ALERTS_FOUND
      end

    render "businesses/security_center/code_scanning/index", locals: {
      business: this_business,
      authorized_orgs: authorized_orgs,
      sso_payload:,
      error_occurred: error_occurred,
      alert_results: paged_results,
      open_count: open_count,
      closed_count: closed_count,
      query: query,
      alerts_code_scanning_index_path_method: method(:security_center_alerts_code_scanning_enterprise_path),
      blankslate_text: blankslate_text,
      menu_data_list: menu_data_list,
      alert_number_plus_repository_id_to_assignees:,
    }
  end

  def menu_content # rubocop:todo GitHub/UseRestfulActions
    if params[:dropdown_type] == SEVERITY_FILTER_NAME
      render CodeScanning::AlertListActionMenuComponent.new(
        id: params[:menu_id],
        header: "Filter by severity",
        caption: "Severity",
        select_variant: :multiple,
        options: severity_menu_options,
        show_clear: query.contains_qualifier?(name: :severity),
        clear_path: clear_path(:severity),
        list_only: true,
      ), layout: false
    elsif params[:dropdown_type] == ORG_FILTER_NAME
      render CodeScanning::AlertListSelectPanelComponent.new(
        caption: "Organization",
        header: "Filter by organization",
        select_variant: :multiple,
        options: SecurityCenterHelper.sort_items_with_counts(org_menu_options(params[:q])),
        show_clear: query.contains_qualifier?(name: :org),
        clear_path: clear_path(:org),
        list_only: true,
      ), layout: false
    elsif params[:dropdown_type] == RULE_FILTER_NAME
      render CodeScanning::AlertListSelectPanelComponent.new(
        caption: "Rule",
        header: "Filter by rule",
        select_variant: :multiple,
        options: SecurityCenterHelper.sort_items_with_counts(rule_menu_options(params[:q])),
        show_clear: query.contains_qualifier?(name: :rule),
        clear_path: clear_path(:rule),
        list_only: true,
      ), layout: false
    elsif params[:dropdown_type] == TOOL_FILTER_NAME
      render CodeScanning::AlertListSelectPanelComponent.new(
        caption: "Tool",
        header: "Filter by tool",
        select_variant: :multiple,
        options: SecurityCenterHelper.sort_items_with_counts(tool_menu_options(params[:q])),
        show_clear: query.contains_qualifier?(name: :tool),
        clear_path: clear_path(:tool),
        list_only: true,
      ), layout: false
    elsif params[:dropdown_type] == REPO_FILTER_NAME
      render CodeScanning::AlertListSelectPanelComponent.new(
        caption: "Repository",
        header: "Filter by repository",
        select_variant: :multiple,
        options: SecurityCenterHelper.sort_items_with_counts(repo_menu_options(params[:q])),
        show_clear: query.contains_qualifier?(name: :repo),
        clear_path: clear_path(:repo),
        list_only: true,
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

  sig { override.returns(Symbol) }
  def authorized_orgs_actions
    :read_code_scanning
  end

  sig { returns(CodeScanning::AlertQueryService) }
  memoize def alert_query_service
    CodeScanning::AlertQueryService.for_business(
      user: current_user,
      user_session: user_session,
      business: this_business,
      organizations: authorized_orgs,
      query: query_string,
      visibility: limited_visibility? ? "public" : nil
    )
  end

  sig { params(qualifier: Symbol).returns(String) }
  def clear_path(qualifier)
    security_center_alerts_code_scanning_enterprise_path(
      this_business,
      query: query.remove_qualifier(qualifier),
    )
  end

  def limited_visibility?
    SecurityCenter::SecurityFeatures.limited_security_center_available?(this_business, dotcom_request_only: true)
  end

  memoize def query
    Search::Queries::SecurityCenter::CodeScanningBusinessQuery.new(query_string)
  end

  def query_string
    params[:query]&.strip || "is:open"
  end

  sig { params(search_string: T.nilable(String)).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def org_menu_options(search_string = nil)
    return [] if authorized_orgs.empty?

    repository_ids_and_alert_counts = alert_query_service.repository_ids_from_filters
    return [] if repository_ids_and_alert_counts.blank?

    alert_count_by_repo_id = repository_ids_and_alert_counts.each_with_object({}) do |repo, hash|
      hash[repo.repository_id] = repo.alert_count
    end

    org_name_by_id = authorized_orgs.each_with_object({}) do |org, hash|
      hash[org.id] = org.display_login if search_string.blank? || org.display_login.downcase.include?(search_string.downcase)
    end

    RepositorySecurityCenterConfig
      .with_owners_under_business(this_business, org_name_by_id.keys, include_emus: false)
      .where(repository_id: alert_count_by_repo_id.keys)
      .select(:owner_id, :repository_id)
      .each_with_object({}) do |row, hash|
        org_name = org_name_by_id[row.owner_id]
        alert_count = alert_count_by_repo_id[row.repository_id]

        hash[org_name] ||= 0
        hash[org_name] += alert_count
      end
      .map do |org_name, alert_count|
        {
          count: alert_count,
          label: org_name,
          selected: query.has_org?(org_name),
          url: security_center_alerts_code_scanning_enterprise_path(
            this_business,
            query: query.add_or_remove(ORG_FILTER_NAME.to_sym, org_name)
          )
        }
      end
  end

  sig { params(search_string: T.nilable(String)).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def repo_menu_options(search_string = nil)
    return [] if alert_query_service.selected_organizations.empty?
    alert_counts_by_repo_id = alert_query_service.repository_ids_for_repo_menu.index_by(&:repository_id)

    Repository.where(owner_id: alert_query_service.selected_organizations, id: alert_counts_by_repo_id.keys).filter_map do |repo|
      {
        label: repo.name,
        sublabel: repo.owner_display_login,
        count: alert_counts_by_repo_id[repo.id].alert_count,
        selected: query.has_nwo?(repo.name_with_display_owner),
        url: security_center_alerts_code_scanning_enterprise_path(
          this_business,
          query: query.add_or_remove(REPO_FILTER_NAME.to_sym, repo.name_with_display_owner)
        ),
      } if search_string.blank? || repo.name&.include?(search_string) || repo.owner_display_login.include?(search_string)
    end
  end

  sig { params(search_string: T.nilable(String)).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def tool_menu_options(search_string = nil)
    alert_query_service
      .tool_names_for_org
      .filter_map do |tool_alert_count|
        {
          label: tool_alert_count.name,
          count: tool_alert_count.alert_count,
          selected: query.qualifier_selected?(name: Search::Queries::SecurityCenter::CodeScanningBaseQuery::QUALIFIER_TOOL, value: tool_alert_count.name),
          url: security_center_alerts_code_scanning_enterprise_path(
            this_business,
            query: query.add_or_remove(TOOL_FILTER_NAME.to_sym, tool_alert_count.name)
          ),
        } if search_string.blank? || tool_alert_count.name.downcase.include?(search_string.downcase)
      end
  end

  def rule_menu_options(search_query = nil)
    alert_query_service
      .rules_for_org(search_query)
      .map do |rule_alert_count|
        {
          label: rule_alert_count.short_description,
          sublabel: rule_alert_count.sarif_identifier,
          count: rule_alert_count.alert_count,
          selected: query.qualifier_selected?(name: Search::Queries::SecurityCenter::CodeScanningBaseQuery::QUALIFIER_RULE, value: rule_alert_count.sarif_identifier),
          url: security_center_alerts_code_scanning_enterprise_path(
            this_business,
            query: query.add_or_remove(RULE_FILTER_NAME.to_sym, rule_alert_count.sarif_identifier)
          ),
        }
      end
  end

  def severity_menu_options
    count_results = alert_query_service.severities_for_org.index_by(&:severity)

    severity_to_option = -> (severity) do
      key = "SEVERITY_#{severity.to_s.upcase}".to_sym
      label = severity.to_s.capitalize
      slug = severity.to_s.downcase
      count = count_results[key]&.alert_count || 0

      {
        label: label,
        count: count,
        selected: query.qualifier_selected?(name: Search::Queries::SecurityCenter::CodeScanningBaseQuery::QUALIFIER_SEVERITY, value: slug),
        url: security_center_alerts_code_scanning_enterprise_path(
          this_business,
          query: query.add_or_remove(SEVERITY_FILTER_NAME.to_sym, slug)
        )
      }
    end

    {
      "Security" => CodeScanningHelper::SECURITY_SEVERITIES.map { |severity| severity_to_option.call(severity) },
      "Other" => CodeScanningHelper::SEVERITIES.map { |severity| severity_to_option.call(severity) }
    }
  end

  sig { params(search_string: T.nilable(String)).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def tag_options(search_string = nil)
    alert_query_service
      .rule_tags_for_org
      .filter_map do |org_rule_tag|
        {
          label: org_rule_tag.tag,
          count: org_rule_tag.alert_count,
        } if search_string.blank? || org_rule_tag.tag.downcase.include?(search_string.downcase)
      end
  end

  def suggestions_for_filter(filter_name)
    case filter_name
    when ORG_FILTER_NAME
      org_menu_options.reject { |option| option[:count] == 0 }.map do |option|
        { value: Search::ParsedQuery.encode_value(option[:label]) }
      end
    when REPO_FILTER_NAME
      repo_menu_options.reject { |option| option[:count] == 0 }.map do |option|
        { value: Search::ParsedQuery.encode_value("#{option[:sublabel]}/#{option[:label]}") }
      end
    when TOOL_FILTER_NAME
      tool_menu_options.reject { |option| option[:count] == 0 }.map do |option|
        { value: Search::ParsedQuery.encode_value(option[:label]) }
      end
    when RULE_FILTER_NAME
      rule_menu_options.reject { |option| option[:count] == 0 }.map do |option|
        {
          value: Search::ParsedQuery.encode_value(option[:sublabel]),
          description: option[:label],
        }
      end
    when TAG_FILTER_NAME
      tag_options.reject { |option| option[:count] == 0 }.map do |option|
        { value: Search::ParsedQuery.encode_value(option[:label]) }
      end
    else
      []
    end.compact.sort_by { |suggestion| suggestion[:value] }
  end

  def menu_data_list
    [
      ::SecurityCenter::SelectPanelComponent::Data.new(
        title: "Teams",
        header: "Filter by team",
        options_src: security_center_options_enterprise_path({
          "options-type": "teams",
          qualifier: ::Search::Queries::SecurityCenter::CodeScanningBaseQuery::QUALIFIER_TEAM,
          query: query.user_query,
          multiselect: true
        }),
      )
    ]
  end

  def check_feature_enabled
    render_404 unless SecurityCenter::SecurityFeatures.code_scanning_enabled_for_instance?
  end

  def security_center_required
    render_404 unless SecurityCenter::SecurityFeatures.security_center_available?(this_business, dotcom_request_only: true)
  end
end
