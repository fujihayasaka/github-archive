# typed: true
# frozen_string_literal: true

class Orgs::SecurityCenter::CodeScanningController < Orgs::SecurityCenter::AbstractSecurityCenterController
  include CodeScanningHelper
  include Orgs::SecurityCenter::CodeScanningOrgQueriesHelper
  include ApplicationHelper
  include SecurityCampaigns::CampaignsSerializer

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Iam,
    ApplicationRecord::Billing,
    ApplicationRecord::IssuesPullRequests,
    only: [:index]

  depends_on_clusters \
    ApplicationRecord::Mysql5,
    ApplicationRecord::SecurityOverviewAnalytics,
    only: [
      :index,
      :repository_list,
      :rule_list,
      :severity_list,
      :tag_list,
      :tool_list,
    ],
    optional: true

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Iam,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Notify,
    ApplicationRecord::Billing,
    only: [:repository_list, :rule_list, :severity_list, :tag_list, :tool_list]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :repository_list, :tool_list, :severity_list, :tag_list, :rule_list], optional: true

  BLANKSLATE_ERROR_OCCURRED = "Loading code scanning alerts failed"
  BLANKSLATE_TOO_MANY_PAGES = "There were too many results, please narrow down your search"
  BLANKSLATE_NO_ALERTS_FOUND = "No code scanning alerts found"

  skip_before_action :cap_pagination, unless: :robot?
  before_action :organization_read_required
  before_action :feature_required
  before_action :security_center_required

  # Background process
  after_action :ensure_security_overview_analytics_reconciliation, only: [:index]
  after_action :trigger_security_overview_analytics_backfill, only: [:index]

  track_latency_slo "p99-ui-request", 3000, only: [:index]
  track_latency_slo "p50-ui-request", 750, only: [:index]

  def index
    per_page = 25

    template_id = params[:template].is_a?(String) ? params[:template].to_sym : nil
    template = SecurityCampaigns::CampaignTemplates::ALL_TEMPLATES[template_id]
    if template.present?
      autofix_enabled = CodeScanning::Autofix.any_enabled_for_org?(this_organization)
      params[:query] = template.build_query(autofix_enabled)
    end

    security_campaign_number = params[:source_campaign_number]
    serialized_source_campaign = nil
    if SecurityCampaigns.campaigns_ga_enabled?(current_user) && security_campaign_number.present?
      source_campaign = SecurityCampaigns::SecurityCampaign.published.find_by(number: security_campaign_number, organization: this_organization)
      if source_campaign.present?
        serialized_source_campaign = serialized_campaign(security_campaign: source_campaign, owner_display_login: this_organization.display_login, current_user:)
      end
    end

    backfill_triggered = this_organization.trigger_security_center_reconciliation

    # For org members with partial repo access, we need to show a warning if they've exceeded the max number of repos we show.
    _, repo_limit_exceeded = allowed_repo_ids_and_limit_exceeded

    # For "invalid" queries, short circuit here and return a blankslate.
    if !query.is_valid?
      return render "orgs/security_center/alerts_code_scanning", locals: {
        backfill_in_progress: backfill_triggered,
        error_occurred: false,
        organization: this_organization,
        alert_results: ::Resiliency::Responses::WillPaginateCollection.new, # empty paged result
        org_campaigns_count: 0,
        open_count: 0,
        closed_count: 0,
        query: query,
        alerts_code_scanning_index_path_method: method(:security_center_alerts_code_scanning_path),
        blankslate_text: BLANKSLATE_NO_ALERTS_FOUND,
        show_incomplete_data_warning: repo_limit_exceeded,
        show_alert_trend_chart: false,
        show_alert_summaries: false,
        team_filter_menu_data: team_filter_menu_data,
        alert_number_plus_repository_id_to_issues: {},
        template:,
        template_dialog: SecurityCampaigns::CampaignTemplates::DIALOG,
        source_campaign: serialized_source_campaign
      }
    end

    # Tenant filtering was performed in alerts_by_repo so the results here are already filtered
    alert_results, repos_by_id, open_count, closed_count, has_error = alert_query_service.alerts_by_repo(
      page: current_page,
      per_page: per_page
    )

    # Paging
    total_count = query.closed? ? closed_count : open_count
    paged_results = WillPaginate::Collection.create(current_page, per_page, total_count) do |pager|
      pager.replace(alert_results || [])
    end

    blankslate_text = if has_error
      BLANKSLATE_ERROR_OCCURRED
    elsif current_page >= 400 # no results after page 399
      BLANKSLATE_TOO_MANY_PAGES
    elsif alert_results.size <= 0
      BLANKSLATE_NO_ALERTS_FOUND
    else
      nil
    end

    # Find the issues tracking paged_results
    alert_number_plus_repository_id_to_issues = alerts_issues(results: paged_results)

    render "orgs/security_center/alerts_code_scanning", locals: {
      backfill_in_progress: backfill_triggered,
      error_occurred: has_error,
      organization: this_organization,
      alert_results: paged_results,
      org_campaigns_count: org_campaigns_count,
      campaign_creation_path: create_security_campaigns_path,
      campaign_managers_path: security_center_security_campaigns_managers_path,
      campaign_alerts_summary_path: security_center_security_campaigns_alerts_summary_path,
      open_count: open_count,
      closed_count: closed_count,
      repos_by_id: repos_by_id,
      query: query,
      alerts_code_scanning_index_path_method: method(:security_center_alerts_code_scanning_path),
      blankslate_text: blankslate_text,
      show_incomplete_data_warning: repo_limit_exceeded,
      team_filter_menu_data: team_filter_menu_data,
      alert_number_plus_repository_id_to_issues:,
      template:,
      template_dialog: SecurityCampaigns::CampaignTemplates::DIALOG,
      source_campaign: serialized_source_campaign
    }
  end

  def repository_list # rubocop:todo GitHub/UseRestfulActions
    results = alert_query_service.repository_ids_for_repo_menu

    repo_ids_and_names = []
    options = []
    if results.present?
      counts_by_repo_id = results.index_by(&:repository_id)
      repo_ids = results.map(&:repository_id).uniq
      repo_ids_and_names = this_organization.repositories.where(id: repo_ids).order(:name).pluck(:id, :name)

      options = repo_ids_and_names.filter_map do |repo_id, repo_name|
        {
          label: repo_name,
          selected: query.has_repository?(repo_name),
          url: security_center_alerts_code_scanning_path(org: this_organization, params: {
            query: query.add_or_remove(:repo, repo_name)
          }),
          count: counts_by_repo_id[repo_id]&.alert_count || 0
        } if params[:q].blank? || repo_name.include?(params[:q])
      end

      options = SecurityCenterHelper.sort_items_with_counts(options)
    end

    respond_to do |format|
      format.html_fragment do
        render CodeScanning::AlertListSelectPanelComponent.new(
          caption: "Repository",
          header: "Filter by Repository",
          select_variant: :multiple,
          options: options,
          show_clear: query.contains_qualifier?(name: :repo),
          clear_path: security_center_alerts_code_scanning_path(query: query.remove_qualifier(:repo)),
          list_only: true,
        )
      end
      format.json do
        repos_list = repo_ids_and_names.map { |_, repo_name| { value: Search::ParsedQuery.encode_value(repo_name) } }
        render json: repos_list || []
      end
    end
  end

  def tool_list # rubocop:todo GitHub/UseRestfulActions
    tools = alert_query_service.tool_names_for_org

    options = tools.map do |tool|
      tool_name = tool.name
      {
        label: tool_name,
        selected: query.qualifier_selected?(name: :tool, value: tool_name),
        url: security_center_alerts_code_scanning_path(query: query.add_or_remove(:tool, tool_name)),
        count: tool.alert_count
      }
    end

    options = SecurityCenterHelper.sort_items_with_counts(options)

    respond_to do |format|
      format.html do
        render CodeScanning::AlertListActionMenuComponent.new(
          id: "code-scanning-tool-filter",
          caption: "Tool",
          header: "Filter by tool",
          select_variant: :multiple,
          options: options,
          show_clear: query.contains_qualifier?(name: :tool),
          clear_path: security_center_alerts_code_scanning_path(query: query.remove_qualifier(:tool)),
          list_only: true,
        ), layout: false
      end
      format.json do
        tools_list = tools.map { |tool| { value: Search::ParsedQuery.encode_value(tool.name) } }
        render json: tools_list || []
      end
    end
  end

  def rule_list # rubocop:todo GitHub/UseRestfulActions
    rules = alert_query_service.rules_for_org(params[:q])

    options = rules.map do |rule|
      {
        label: rule.short_description,
        sublabel: rule.sarif_identifier,
        selected: query.qualifier_selected?(name: :rule, value: rule.sarif_identifier),
        url: security_center_alerts_code_scanning_path(query: query.add_or_remove(:rule, rule.sarif_identifier)),
        count: rule.alert_count
      }
    end.reject { |option| option[:label] == "All" }

    options = SecurityCenterHelper.sort_items_with_counts(options)

    respond_to do |format|
      format.html_fragment do
        render CodeScanning::AlertListSelectPanelComponent.new(
          caption: "Rule",
          header: "Filter by rule",
          select_variant: :multiple,
          options: options,
          show_clear: query.contains_qualifier?(name: :rule),
          clear_path: security_center_alerts_code_scanning_path(query: query.remove_qualifier(:rule)),
          list_only: true,
        ), layout: false
      end
      format.json do
        rules_list = rules.map { |rule| { value: Search::ParsedQuery.encode_value(rule.sarif_identifier), description: rule.short_description } }
        render json: rules_list
      end
    end
  end

  def severity_list # rubocop:todo GitHub/UseRestfulActions
    severity_options = {
      "Security" => [],
      "Other" => []
    }

    severities = {
      "Security" => security_severity_symbols.map { |sym| { label: sym.to_s.downcase } },
      "Other" => severity_symbols.map { |sym| { label: sym.to_s.downcase } }
    }

    severities.each do |key, options|
      options.each do |item|
        severity = item[:label]
        severity_sym = ("SEVERITY_#{severity.upcase}").to_sym

        severity_options[key] << {
          label: severity.capitalize,
          selected: query.qualifier_selected?(name: :severity, value: severity),
          url: security_center_alerts_code_scanning_path(query: query.add_or_remove(:severity, severity)),
          count: counts_by_severity[severity_sym]&.alert_count || 0
        }
      end
    end

    respond_to do |format|
      format.html do
        render CodeScanning::AlertListActionMenuComponent.new(
          id: "code-scanning-severity-filter",
          caption: "Severity",
          header: "Filter by severity",
          list_only: true,
          options: severity_options,
          show_clear: query.contains_qualifier?(name: :severity),
          clear_path: security_center_alerts_code_scanning_path(
            org: this_organization,
            query: query.remove_qualifier(:severity)
          ),
          select_variant: :multiple
        ), layout: false
      end
    end
  end

  def tag_list # rubocop:todo GitHub/UseRestfulActions
    tools = alert_query_service.rule_tags_for_org

    options = tools.map do |tag|
      tag_name = tag.tag
      {
        label: tag_name,
        selected: query.qualifier_selected?(name: :tag, value: tag_name),
        url: security_center_alerts_code_scanning_path(query: query.add_or_remove(:tag, tag_name)),
        count: tag.alert_count,
      }
    end

    options = SecurityCenterHelper.sort_items_with_counts(options)

    respond_to do |format|
      format.html do
        render CodeScanning::AlertListActionMenuComponent.new(
          id: "code-scanning-tag-filter",
          caption: "Tag",
          header: "Filter by rule tag",
          select_variant: :multiple,
          options: options,
          show_clear: query.contains_qualifier?(name: :tag),
          clear_path: security_center_alerts_code_scanning_path(query: query.remove_qualifier(:tag)),
          list_only: true,
        ), layout: false
      end
      format.json do
        tags_list = tools.map { |tag| { value: Search::ParsedQuery.encode_value(tag.tag) } }
        render json: tags_list
      end
    end
  end

  private

  def feature_required
    render_404 unless SecurityCenter::SecurityFeatures.code_scanning_enabled_for_instance?
  end

  def security_center_required
    render_404 unless SecurityCenter::SecurityFeatures.security_center_available?(this_organization, dotcom_request_only: true)
  end

  def team_filter_menu_data
    return if this_organization.teams.size > TEAM_DROPDOWN_THRESHOLD

    qualifier = ::Search::Queries::SecurityCenter::CodeScanningBaseQuery::QUALIFIER_TEAM
    include_clear = query.contains_qualifier?(name: qualifier)
    clear_href = "?query=#{query.remove_qualifier(qualifier)}"

    ::SecurityCenter::Coverage::SelectMenuComponent::Data.new(
      name: "Teams",
      header: "Filter by team",
      filter: ::SecurityCenter::Coverage::SelectMenuComponent::Filter.new(placeholder: "Filter teams"),
      options_src: security_center_options_path(
        "options-type": "teams",
        qualifier: qualifier,
        query: query.user_query,
        multiselect: true,
      ),
      clear_option: (::SecurityCenter::Coverage::SelectMenuComponent::ClearOption.new(
        text: "Clear teams",
        href: clear_href,
      ) if include_clear),
    )
  end

  memoize def counts_by_severity
    alert_query_service
      .severities_for_org
      .index_by(&:severity)
  end

  memoize def table_alerts_count
    selected_severities = query.severities.map { |s| ("SEVERITY_#{s.to_s.upcase}").to_sym }
    security_severities = security_severity_symbols.map { |s| ("SEVERITY_#{s.to_s.upcase}").to_sym }
    # exclude informational alert counts and non-selected severities from the total
    included_severities = selected_severities.present? ? selected_severities : security_severities
    counts_by_severity.values_at(*included_severities).compact.sum(&:alert_count)
  end

  def org_campaigns_count
    return 0 unless SecurityCampaigns.enabled?(this_organization)

    SecurityCampaigns::SecurityCampaign.open.where(organization_id: this_organization.id).count
  end
end
