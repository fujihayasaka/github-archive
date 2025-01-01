# typed: true
# frozen_string_literal: true

# This search bar component is used for alert filtering at both the organization level
# (passing an `organization` parameter) and the repository level (passing a `repository`
# parameter). Which parameter is passed affects the filters offered to the user.
# If both are passed, `organization` is ignored.
class CodeScanning::AlertFilterComponent < GitHub::FilterInputComponent
  include CodeScanningHelper

  def initialize(
    user:,
    repository: nil,
    organization: nil,
    business: nil,
    language_percentages: [],
    query:,
    default_query_string: "is:open",
    autofix_generated_filter_enabled: false,
    autofix_accepted_filter_enabled: false,
    autofix_allowed_by_entity: false
  )
    @user = user
    @repository = repository
    @owner = @repository.owner if @repository.present?
    @organization = organization
    @business = business
    @language_percentages = language_percentages
    @query = query
    @autofix_generated_filter_enabled = autofix_generated_filter_enabled
    @autofix_accepted_filter_enabled = autofix_accepted_filter_enabled
    @autofix_allowed_by_entity = autofix_allowed_by_entity

    super(
      tag_name: "code-scanning-alert-filter",
      use_pjax: true,
      placeholder: "Filter alerts",
      query: suggestable_input_value,
      suggestable_items: suggestable_items,
      default_value: default_query_string,
      my: 0,
    )
  end

  def suggestable_items
    common_suggestions = [
      :is,
      :tool,
      :rule,
      :tag,
      :severity,
      :sort,
      :resolution,
      :autofilter,
    ]

    if @repository&.code_scanning_alert_assignment_management_enabled? ||
        @organization&.feature_flag_enabled?(:code_scanning_alert_assignment_management, default: false) ||
          @business&.feature_flag_enabled?(:code_scanning_alert_assignment_management, default: false)
      common_suggestions.push(:assignee, :has, :no)
    end

    # The autofix filter is not shown for users and organizations that have opted out of autofix.
    common_suggestions.push(:autofix) if @autofix_allowed_by_entity

    repo_only_suggestions = [
      :branch,
      :pr,
      :ref,
      :path,
      :language,
    ]

    biz_only_suggestions = [
      :repo,
      :org,
      :team,
      :topic,
    ]

    all_qualifiers = {
      is: { description: "filter by open/closed state", suggestions: suggestable_states },
      repo: { description: "filter by repository", negatable: @organization.present? },
      org: { description: "filter by organization", negatable: @business.present? },
      tool: { description: "filter by tool", negatable: true },
      branch: { description: "filter by branch name" }, # this is handled by special logic in the TypeScript
      pr: { description: "filter by pr number", suggestions: [] },
      ref: { description: "filter by ref (e.g. branches/tags)" },
      rule: { description: "filter by rule", negatable: true },
      tag: { description: "filter by rule tag", negatable: true },
      severity: { description: "filter by severity", suggestions: suggestable_severities, negatable: true },
      sort: { description: "sort by", suggestions: suggestable_sorts },
      autofilter: { description: "only show alerts in application code", suggestions: suggestable_autofilter_options },
      resolution: { description: "filter by closure reason", suggestions: suggestable_closure_reasons, negatable: true },
      team: { description: "filter by team name", negatable: true },
      topic: { description: "filter by repository topic", negatable: true },
      path: { description: "filter by file path (e.g. lib/crypto or *_test.js)" },
      language: { description: "filter by language", suggestions: suggestable_language_options },
      autofix: { description: "filter by autofix state", suggestions: suggestable_autofix_states, negatable: true },
      assignee: { description: "filter by assignee", negatable: true },
      has: { description: "filter by presence of a property", suggestions: has_suggestions },
      no: { description: "filter by absence of a property", suggestions: no_suggestions },
    }

    # Custom properties should always be last in the list.
    if custom_properties_helpers.present?
      T.must(custom_properties_helpers).definitions_for_frontend.each do |prop_definition|
        all_qualifiers["props.#{prop_definition.fetch(:name)}".to_sym] = {
          description: "Custom property: #{prop_definition.fetch(:name)}",
          negatable: true
        }
      end
    end

    suggestion_paths.each do |key, path|
      next unless all_qualifiers.key?(key)
      all_qualifiers[key][:path] = path
    end

    if @repository.present?
      all_qualifiers.select { |key, _| repo_only_suggestions.include?(key) || common_suggestions.include?(key) }
    elsif @organization.present?
      all_qualifiers.select { |key, _| org_only_suggestions.include?(key) || common_suggestions.include?(key) }
    elsif @business.present?
      all_qualifiers.select { |key, _| biz_only_suggestions.include?(key) || common_suggestions.include?(key) }
    else
      []
    end
  end

  sig { returns(T::Array[Symbol]) }
  def org_only_suggestions
    qualifiers = [:repo, :team, :topic]

    if custom_properties_helpers.present?
      T.must(custom_properties_helpers).definitions_for_frontend.each do |prop_definition|
        qualifiers << "props.#{prop_definition.fetch(:name)}".to_sym
      end
    end

    qualifiers
  end

  sig { returns(T.nilable(::SecurityCenter::Helpers::CustomProperties)) }
  def custom_properties_helpers
    return if @organization.blank?
    ::SecurityCenter::Helpers::CustomProperties.new(org: @organization, user: @user)
  end

  def suggestion_paths
    if @repository.present?
      {
        ref: repository_index_refs_path(@repository, @query, format: :json),
        rule: repository_index_rules_path(@repository, @query, format: :json),
        tag: repository_index_tags_path(@repository, @query, format: :json),
        tool: repository_index_tools_path(@repository, @query, format: :json),
        assignee: urls._filter_users_path(repo: @repository.name_with_display_owner),
      }
    elsif @organization.present?
      paths = {
        tool: security_center_code_scanning_tool_list_json_path(@organization, query: @query.user_query),
        rule: security_center_code_scanning_rule_list_json_path(@organization, query: @query.user_query),
        tag: security_center_code_scanning_tag_list_json_path(@organization, query: @query.user_query),
        repo: security_center_code_scanning_repository_list_json_path(@organization, query: @query.user_query),
        team: security_center_code_scanning_teams_list_json_path(@organization),
        topic: security_center_code_scanning_topics_list_json_path(@organization),
        assignee: urls._filter_users_path
      }

      if custom_properties_helpers.present?
        T.must(custom_properties_helpers).definitions_for_frontend.each do |prop_definition|
          prop_name = prop_definition.fetch(:name)
          paths["props.#{prop_name}".to_sym] = security_center_code_scanning_custom_property_list_json_path(@organization, prop_name)
        end
      end

      paths
    elsif @business.present?
      path_method = -> (filter_name) {
        security_center_alerts_code_scanning_filter_input_suggestions_enterprise_json_path(
          @business,
          filter_name: filter_name,
        )
      }

      {
        org: path_method.call(Businesses::SecurityCenter::CodeScanningController::ORG_FILTER_NAME),
        repo: path_method.call(Businesses::SecurityCenter::CodeScanningController::REPO_FILTER_NAME),
        tool: path_method.call(Businesses::SecurityCenter::CodeScanningController::TOOL_FILTER_NAME),
        rule: path_method.call(Businesses::SecurityCenter::CodeScanningController::RULE_FILTER_NAME),
        tag: path_method.call(Businesses::SecurityCenter::CodeScanningController::TAG_FILTER_NAME),
        team: security_center_alerts_code_scanning_options_enterprise_json_path(@business, filter_name: "teams"),
        topic: security_center_alerts_code_scanning_options_enterprise_json_path(@business, filter_name: "topics"),
        assignee: urls._filter_users_path,
      }
    end
  end

  def suggestable_input_value
    @suggestable_input_value ||= begin
      value = @query.query_string&.rstrip
      value.blank? ? "" : "#{value} "
    end
  end

  def suggestable_severities
    (severity_symbols + security_severity_symbols).map { |severity_symbol| { value: severity_symbol.to_s.downcase } }
  end

  def suggestable_sorts
    SORT_OPTIONS.map { |sort| { value: sort[:query], description: sort[:label] } }
  end

  def suggestable_states
    [
      { value: "open", description: "Open alerts" },
      { value: "closed", description: "Closed alerts" },
    ]
  end

  def suggestable_closure_reasons
    RESOLUTION_OPTIONS.map { |resolution| { value: resolution[:query], description: resolution[:label] } }
  end

  def suggestable_autofilter_options
    [
      { value: "true", description: "Only show alerts in application code" },
    ]
  end

  def suggestable_autofix_states
    suggested = T.let([], T::Array[T::Hash[Symbol, String]])
    suggested.push({ value: "supported", description: "Eligible for a Copilot Autofix suggestion" })
    suggested.push({ value: "generated", description: "A Copilot Autofix suggestion has been generated" }) if @autofix_generated_filter_enabled
    suggested.push({ value: "accepted", description: "A Copilot Autofix suggestion has been accepted" }) if @autofix_accepted_filter_enabled
    suggested
  end

  def suggestable_language_options
    if @language_percentages.present?
      @language_percentages.map do |language, _|
        { value: language.downcase, description: "#{language}" }
      end
    end
  end

  def has_suggestions
    [
      { value: "assignee", description: "has an assignee" },
    ]
  end

  def no_suggestions
    [
      { value: "assignee", description: "has no assignee" },
    ]
  end
end
