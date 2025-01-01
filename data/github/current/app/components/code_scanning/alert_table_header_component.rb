# typed: true
# frozen_string_literal: true

class CodeScanning::AlertTableHeaderComponent < ApplicationComponent
  include CodeScanningHelper
  include LanguageHelper

  attr_reader :open_count, :closed_count, :open_path, :closed_path, :repository, :organization, :query, :current_user, :ref_names, :fixed_result_numbers

  def initialize(
    open_count:,
    closed_count:,
    query:,
    open_path:,
    closed_path:,
    repository: nil,
    organization: nil,
    business: nil,
    current_user:,
    ref_names:,
    fixed_result_numbers:,
    language_percentages:
  )
    @open_count = open_count
    @closed_count = closed_count
    @query = query
    @open_path = open_path
    @closed_path = closed_path
    @repository = T.let(repository, T.nilable(Repository))
    @organization = organization
    @business = business
    @owner = @repository.owner if @repository.present?
    @current_user = current_user
    @ref_names = ref_names
    @fixed_result_numbers = fixed_result_numbers
    @language_percentages = language_percentages
  end

  def select_menus
    Array.new.tap do |select_menu|
      select_menu << closed_filter if closed_filter_applied? || has_no_state_selection?
      select_menu << organization_filter if organization_filter.present?
      select_menu << repository_filter if repository_filter.present?
      select_menu << languages_filter if languages_filter.present?
      select_menu << tools_filter if tools_filter.present?
      select_menu << rules_filter if rules_filter.present?
      select_menu << severity_filter if severity_filter.present?
      select_menu << sort_filter if sort_filter.present?
    end
  end

  def actions
    if @repository.present?
      CodeScanning::AlertTableActionComponent.new(
        query: @query,
        alerts_writable: alerts_writable_by_user?(@repository, @current_user),
        close_path: close_alert_path,
        reopen_path: repository_code_scanning_reopen_path(@owner, @repository, number: nil, ref_names: @ref_names),
        fixed_result_numbers: @fixed_result_numbers,
        dismiss_alert_button_label: dismiss_alert_button_label,
        require_dismissal_comment: require_dismissal_comment?
      )
    end
  end

  def close_alert_path
    return urls.repository_code_scanning_dismissal_request_create_path(repository.owner, repository) if CodeScanning::AlertDismissalService.new(repository).enabled?
    repository_code_scanning_close_path(@owner, @repository, number: nil, reason: nil, ref_names: @ref_names)
  end

  def dismiss_alert_button_label
    return "Submit request" if CodeScanning::AlertDismissalService.new(repository).enabled?
    "Dismiss alert"
  end

  def has_both_state_filters?
    @query.closed? && @query.open?
  end

  def has_no_state_selection?
    !(closed_filter_applied? || open_filter_applied?)
  end

  def closed_filter_applied?
    @query.closed?
  end

  def open_filter_applied?
    @query.open?
  end

  private

  def closed_filter_options
    RESOLUTION_OPTIONS.map do |details|
      {
        label: details[:label],
        selected: @query.qualifier_selected?(name: :resolution, value: details[:query]),
        url: index_path(query: @query.add_or_remove(:resolution, details[:query])),
      }
    end
  end

  def closed_filter
    CodeScanning::AlertListActionMenuComponent.new(
      id: "code-scanning-closed-filter",
      caption: "Closed as",
      header: "Filter by closure reason",
      options: closed_filter_options,
      show_clear: @query.contains_qualifier?(name: :resolution),
      clear_path: index_path(query: @query.remove_qualifier(:resolution)),
      clear_text: "Clear resolutions",
      select_variant: :multiple
    )
  end

  def organization_filter
    return unless @business.present?

    menu_id = "code-scanning-org-filter"
    data_path = security_center_code_scanning_menu_content_enterprise_path(
      @business,
      query: @query.user_query,
      dropdown_type: Businesses::SecurityCenter::CodeScanningController::ORG_FILTER_NAME,
      menu_id: menu_id
    )

    CodeScanning::AlertListSelectPanelComponent.new(
      caption: "Organization",
      header: "Filter by organization",
      select_variant: :multiple,
      data_path: data_path,
      show_clear: @query.contains_qualifier?(name: :org),
      clear_path: index_path(query: @query.remove_qualifier(:org)),
      test_selector: menu_id
    )
  end

  def repository_filter
    menu_id = "code-scanning-repo-filter"

    data_path =
      if @organization.present?
        security_center_code_scanning_repository_list_path(@organization, query: @query.user_query)
      elsif @business.present?
        security_center_code_scanning_menu_content_enterprise_path(
          @business,
          query: @query.user_query,
          dropdown_type: Businesses::SecurityCenter::CodeScanningController::REPO_FILTER_NAME,
          menu_id: menu_id
        )
      end
    return unless data_path.present?

    CodeScanning::AlertListSelectPanelComponent.new(
      caption: "Repository",
      header: "Filter by Repository",
      select_variant: :multiple,
      data_path: data_path,
      show_clear: @query.contains_qualifier?(name: :repo),
      clear_path: index_path(query: @query.remove_qualifier(:repo)),
      test_selector: menu_id
    )
  end

  def languages_filter
    return unless @repository.present?
    return unless @language_percentages.any?

    options = @language_percentages.map do |name, _|
      {
        label: name,
        selected: @query.qualifier_selected?(name: :language, value: name),
        url: index_path(query: @query.add_or_remove(:language, name.downcase)),
        octicon: :"dot-fill",
        octicon_color: language_color(Linguist::Language[name]),
      }
    end

    CodeScanning::AlertListActionMenuComponent.new(
      id: "code-scanning-language-filter",
      caption: "Language",
      header: "Filter by language",
      select_variant: :multiple,
      show_clear: @query.contains_qualifier?(name: :language),
      clear_path: index_path(query: @query.remove_qualifier(:language)),
      options: options,
    )
  end

  def tools_filter
    menu_id = "code-scanning-tool-filter"

    data_path =
      if @repository.present?
        repository_code_scanning_results_tool_list_path(@owner, @repository, query: @query.user_query)
      elsif @organization.present?
        security_center_code_scanning_tool_list_path(@organization, query: @query.user_query)
      elsif @business.present?
        security_center_code_scanning_menu_content_enterprise_path(
          @business,
          query: @query.user_query,
          dropdown_type: Businesses::SecurityCenter::CodeScanningController::TOOL_FILTER_NAME,
          menu_id: menu_id
        )
      end
    return unless data_path.present?

    # At repo and org level (as opposed to enterprise), there's no filter
    # so AlertListActionMenuComponent is enough
    if @repository.present? || @organization.present?
      CodeScanning::AlertListActionMenuComponent.new(
        id: "code-scanning-tool-filter",
        caption: "Tool",
        header: "Filter by tool",
        select_variant: :multiple,
        data_path: data_path,
        show_clear: @query.contains_qualifier?(name: :tool),
        clear_path: index_path(query: @query.remove_qualifier(:tool)),
      )
    else
      CodeScanning::AlertListSelectPanelComponent.new(
        caption: "Tool",
        header: "Filter by tool",
        select_variant: :multiple,
        data_path: data_path,
        show_clear: @query.contains_qualifier?(name: :tool),
        clear_path: index_path(query: @query.remove_qualifier(:tool)),
        test_selector: menu_id
      )
    end
  end

  def rules_filter
    menu_id = "code-scanning-rule-filter"

    data_path =
      if @repository.present?
        repository_code_scanning_results_rule_list_path(@owner, @repository, query: @query.user_query)
      elsif @organization.present?
        security_center_code_scanning_rule_list_path(@organization, query: @query.user_query)
      elsif @business.present?
        security_center_code_scanning_menu_content_enterprise_path(
          @business,
          query: @query.user_query,
          dropdown_type: Businesses::SecurityCenter::CodeScanningController::RULE_FILTER_NAME,
          menu_id: menu_id
        )
      end

    return unless data_path.present?

    CodeScanning::AlertListSelectPanelComponent.new(
      caption: "Rule",
      header: "Filter by rule",
      select_variant: :multiple,
      data_path: data_path,
      show_clear: @query.contains_qualifier?(name: :rule),
      clear_path: index_path(query: @query.remove_qualifier(:rule)),
      test_selector: menu_id
    )
  end

  def index_path(**params)
    if @business.present?
      security_center_alerts_code_scanning_enterprise_path(@business, params)
    elsif @repository.present?
      repository_code_scanning_results_path(@owner, @repository, params)
    elsif @organization.present?
      security_center_alerts_code_scanning_path(org: @organization, params: params)
    end
  end

  def severity_filter_options
    severities = {
      "Filter by severity" => [],
      "Security" => [],
      "Other" => []
    }

    %w[critical high medium low].each do |severity|
      severities["Security"] << {
        label: severity.capitalize,
        selected: @query.qualifier_selected?(name: :severity, value: severity),
        url: index_path(query: @query.add_or_remove(:severity, severity)),
      }
    end

    %w[error warning note].each do |severity|
      severities["Other"] << {
        label: severity.capitalize,
        selected: @query.qualifier_selected?(name: :severity, value: severity),
        url: index_path(query: @query.add_or_remove(:severity, severity)),
      }
    end
    severities
  end

  def severity_filter
    menu_id = "code-scanning-severity-filter"

    options = severity_filter_options if @repository.present? # for now, repo-level severity still hard-coded list
    data_path =
      if @organization.present?
        security_center_code_scanning_severity_list_path(@organization, query: @query.user_query)
      elsif @business.present?
        security_center_code_scanning_menu_content_enterprise_path(
          @business,
          query: @query.user_query,
          dropdown_type: Businesses::SecurityCenter::CodeScanningController::SEVERITY_FILTER_NAME,
          menu_id: menu_id
        )
      end

    CodeScanning::AlertListActionMenuComponent.new(
      id: menu_id,
      caption: "Severity",
      header: "Filter by severity",
      options: options,
      data_path: data_path,
      show_clear: @query.contains_qualifier?(name: :severity),
      clear_path: index_path(query: @query.remove_qualifier(:severity)),
      select_variant: :multiple,
      test_selector: menu_id
    )
  end

  memoize def selected_sort
    SORT_OPTIONS.find { |details| details[:query] == query.sort }
  end

  def sort_options
    SORT_OPTIONS.map do |details|
      {
        label: details[:label],
        selected: selected_sort == details,
        url: index_path(query: query.toggle_qualifier(name: :sort, value: details[:query])),
      }
    end.unshift({
      label: "Most important",
      selected: !query.contains_qualifier?(name: :sort),
      url: index_path(query: query.remove_qualifier(:sort)),
    })
  end

  def sort_filter
    clear_query = @query.remove_qualifier(:sort)

    CodeScanning::AlertListActionMenuComponent.new(
      id: "code-scanning-sort",
      caption: "Sort",
      header: "Sort by",
      options: sort_options,
      no_right_padding: true,
      show_clear: @query.contains_qualifier?(name: :sort),
      clear_text: "Clear sort",
      clear_path: index_path(query: @query.remove_qualifier(:sort))
    )
  end

  def select_menu_core_params
    {
      pr: 3,
      display: :inline_block,
      position: :relative,
      details: { overlay: :default },
      align_right: true,
      is_multiselect: true,
      query: @query.user_query,
      query_parser: @query.class,
    }
  end

  def require_dismissal_comment?
    @repository.present? && CodeScanning::AlertDismissalService.new(@repository).enabled?
  end
end
