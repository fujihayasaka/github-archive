# typed: true
# frozen_string_literal: true

class CodeScanning::Settings::StatusComponent < ApplicationComponent
  include CodeScanningHelper
  include LanguageHelper
  include GitHub::Memoizer

  attr_reader :repository
  attr_reader :auto_codeql_detected_languages
  attr_reader :auto_codeql_debuggable_workflow_run_id
  attr_reader :dismissed_auto_codeql_notice
  attr_reader :latest_workflow_run_id
  attr_reader :latest_successful_codeql_analysis_date
  attr_reader :latest_codeql_analysis_date
  attr_reader :codeql_workflow_path
  attr_reader :configuration
  attr_reader :next_scheduled_run_at
  attr_reader :is_repo_active
  attr_reader :debuggable_configuration
  attr_reader :latest_debuggable_run_id
  attr_reader :disabling_auto_codeql_restricted_by_security_configuration
  attr_reader :enabling_auto_codeql_restricted_by_security_configuration

  def initialize(
    repository:,
    language_display_names: nil,
    runners_error: nil,
    auto_codeql_onboarding_status: nil,
    auto_codeql_detected_languages: [],
    auto_codeql_debuggable_workflow_run_id: nil,
    dismissed_auto_codeql_notice: false,
    latest_workflow_run_id: auto_codeql_debuggable_workflow_run_id,
    latest_successful_codeql_analysis_date: nil,
    latest_codeql_analysis_date: nil,
    latest_codeql_analysis_delivery_origin: nil,
    codeql_workflow_path: nil,
    configuration: nil,
    next_scheduled_run_at: nil,
    is_repo_active: true,
    auto_codeql_setup_failed: false,
    debuggable_configuration: nil,
    has_failed_update: nil,
    latest_debuggable_run_id: nil,
    disabling_auto_codeql_restricted_by_security_configuration: false,
    enabling_auto_codeql_restricted_by_security_configuration: false
  )
    @repository = repository
    @language_display_names = language_display_names
    @runners_error = runners_error
    @auto_codeql_onboarding_status = auto_codeql_onboarding_status
    @auto_codeql_detected_languages = auto_codeql_detected_languages
    @auto_codeql_debuggable_workflow_run_id = auto_codeql_debuggable_workflow_run_id
    @dismissed_auto_codeql_notice = dismissed_auto_codeql_notice
    @latest_workflow_run_id = latest_workflow_run_id
    @latest_successful_codeql_analysis_date = latest_successful_codeql_analysis_date
    @latest_codeql_analysis_date = latest_codeql_analysis_date
    @latest_codeql_analysis_delivery_origin = latest_codeql_analysis_delivery_origin
    @codeql_workflow_path = codeql_workflow_path
    @configuration = configuration
    @next_scheduled_run_at = next_scheduled_run_at
    @is_repo_active = is_repo_active
    @auto_codeql_setup_failed = auto_codeql_setup_failed
    @debuggable_configuration = debuggable_configuration
    @has_failed_update = has_failed_update
    @latest_debuggable_run_id = latest_debuggable_run_id
    @disabling_auto_codeql_restricted_by_security_configuration = disabling_auto_codeql_restricted_by_security_configuration
    @enabling_auto_codeql_restricted_by_security_configuration = enabling_auto_codeql_restricted_by_security_configuration
  end

  def initial_render?
    @auto_codeql_onboarding_status.nil?
  end

  def languages
    configuration.languages
  end

  def query_suite
    configuration.query_suite
  end

  def query_suite_label
    if query_suite == "extended"
      "Extended"
    else
      "Default"
    end
  end

  def query_suite_description
    CodeScanning::AutoCodeql.query_suite_options(repository.owner).find { |suite| suite[:value] == query_suite }&.dig(:description) || ""
  end

  def component_wrapper(&block)
    if initial_render?
      content_tag("include-fragment", src: repository_code_scanning_status_path(repository.owner, repository), data: { test_selector: "initial-render-include-fragment" }, &block)
    elsif auto_codeql_enabling? || auto_codeql_updating?
      content_tag("poll-include-fragment", src: poll_include_fragment_src, &block)
    else
      content_tag(:div, &block)
    end
  end

  def wraper_tag
    if initial_render?
      "include-fragment"
    elsif auto_codeql_enabling?
      "poll-include-fragment"
    else
      "div"
    end
  end

  def retry_button_data_attrs
    case wraper_tag
    when "include-fragment"
      { "data-retry-button" => "" }
    when "poll-include-fragment"
      { "data-target" => "poll-include-fragment.retryButton" }
    else
      {}
    end
  end

  def auto_codeql_disabled?
    @auto_codeql_onboarding_status == "disabled"
  end

  def auto_codeql_enabling?
    %w[enabling onboarding].include?(@auto_codeql_onboarding_status)
  end

  def auto_codeql_updating?
    @auto_codeql_onboarding_status == "updating"
  end

  def auto_codeql_setup_failed?
    @auto_codeql_setup_failed
  end

  def auto_codeql_waiting?
    @auto_codeql_onboarding_status == "waiting"
  end

  def auto_codeql_enabled?
    # TODO: It feels odd that we are redefining this here, it would be better to either call AutoCodeql directly
    #       or have a simple status component that implements these predicates.
    %w[enabled updating stable waiting].include?(@auto_codeql_onboarding_status)
  end

  def failed_update_warning_title
    return unless show_failed_update_warning?

    title = "The default setup for CodeQL failed to enable "
    title += languages_failed_to_enable_during_update.length > 1 ? "multiple languages" : "#{languages_failed_to_enable_during_update[0]}"
    title += debuggable_configuration.creation_trigger == :LANGUAGES_CHANGE ? " automatically" : ""
  end

  def failed_update_warning_main_message
    return unless show_failed_update_warning?

    plural = languages_failed_to_enable_during_update.length > 1

    message = ""
    if debuggable_configuration.creation_trigger == :LANGUAGES_CHANGE
      message = "CodeQL detected "
      message += plural ? "#{languages_failed_to_enable_during_update.to_sentence}" : "#{languages_failed_to_enable_during_update[0]}"
      message += " in this repository and tried to enable #{ plural ? "them" : "it" } automatically without success. "
    elsif plural
      message += "CodeQL tried to enable #{languages_failed_to_enable_during_update.to_sentence} in this repository without success. "
    end
  end

  def show_auto_codeql_setup_error?
    return false if dismissed_auto_codeql_notice

    auto_codeql_setup_failed?
  end

  memoize def languages_removed_during_adjustment
    # The adjusted languages only make sense for a repository that is enabled.
    # We do not want to show them if the repo is updating as it becomes ambiguous which configuration
    # the adjustment refers to.
    return [] if @auto_codeql_onboarding_status != "enabled"

    canonical_languages = @configuration.initial_languages - languages

    canonical_languages.each_with_object([]) do |language, languages_removed|
      languages_removed.append(*@language_display_names[language])
    end
  end

  memoize def languages_failed_to_enable_during_update
    return [] if @debuggable_configuration.nil? || @configuration.nil?

    canonical_languages = @debuggable_configuration.languages - @configuration.languages

    canonical_languages.each_with_object([]) do |language, languages_failed|
      languages_failed.append(*@language_display_names[language])
    end
  end

  def show_auto_codeql_setup_warning?
    return false if dismissed_auto_codeql_notice

    # we need to check @has_failed_update too to because otherwise we may end up showing two banners
    !@has_failed_update && languages_removed_during_adjustment.present?
  end

  memoize def show_failed_update_warning?
    return false if dismissed_auto_codeql_notice

    # for now we only show this banner if the failed update was about languages (and not query suites)
    @has_failed_update && languages_failed_to_enable_during_update.present?
  end

  def runners_error
    @runners_error
  end

  def latest_run_id_for_status_menu
    if auto_codeql_enabling?
      auto_codeql_debuggable_workflow_run_id
    else
      latest_workflow_run_id
    end
  end

  def auto_codeql_debug_url
    if auto_codeql_debuggable_workflow_run_id.present?
      workflow_run_path(
        repository.owner,
        repository,
        auto_codeql_debuggable_workflow_run_id
      )
    else
      actions_path(
        repository.owner,
        repository
      )
    end
  end

  def codeql_documentation_url
    "#{docs_base_url}/code-security/code-scanning/automatically-scanning-your-code-for-vulnerabilities-and-errors/about-code-scanning-with-codeql"
  end

  def codeql_language_documentation_url
    "#{docs_base_url}/code-security/code-scanning/automatically-scanning-your-code-for-vulnerabilities-and-errors/about-code-scanning-with-codeql#about-codeql"
  end

  def eligible_repos_documentation_url
    "#{docs_base_url}/code-security/code-scanning/automatically-scanning-your-code-for-vulnerabilities-and-errors/configuring-code-scanning-at-scale#eligible-repositories-for-codeql-default-setup"
  end

  def query_documentation_url
    path = "/code-security/code-scanning/automatically-scanning-your-code-for-vulnerabilities-and-errors/built-in-codeql-query-suites"
    owner = repository.owner
    base_url = GitHub.help_url(ghec_exclusive: owner.organization? && (owner.business || owner.business_plus?))
    "#{base_url}#{path}"
  end

  def last_scan_url
    "/#{repository.name_with_display_owner}/actions/runs/#{latest_debuggable_run_id}"
  end

  def existing_setup_warning?
    return false if auto_codeql_enabled?

    latest_codeql_analysis_date.present? && @latest_codeql_analysis_delivery_origin != :DELIVERY_ORIGIN_MANAGED
  end

  def existing_api_setup_warning?
    return false if auto_codeql_enabled?

    latest_codeql_analysis_date.present? && @latest_codeql_analysis_delivery_origin == :DELIVERY_ORIGIN_API
  end

  def disabled_schedule_warning?
    return false if auto_codeql_disabled? || auto_codeql_waiting?

    !is_repo_active
  end

  def show_schedule_row?
    return true if auto_codeql_disabled?

    is_repo_active
  end

  def tool_status_page_url
    repository_code_scanning_results_tool_status_show_path(repository.owner, repository, tool_name: "CodeQL")
  end

  def auto_codeql_dialog_id
    "auto-codeql-config-dialog"
  end

  private

  def docs_base_url
    owner = repository.owner
    GitHub.help_url(ghec_exclusive: owner.organization? && (owner.business || owner.business_plus?))
  end

  def poll_include_fragment_src
    query_params = {}

    if auto_codeql_enabling? || auto_codeql_updating?
      if auto_codeql_debuggable_workflow_run_id.blank?
        query_params[:wait_until] = "has_workflow_run"
      else
        query_params[:wait_until] = "completion"
      end
    end

    repository_code_scanning_status_path(repository.owner, repository, **query_params)
  end

  def auto_codeql_language_name(language)
    case language
    when "c-cpp"
      "C / C++"
    when "csharp"
      "C#"
    when "java-kotlin"
      "Java / Kotlin"
    when "javascript-typescript"
      "JavaScript / TypeScript"
    else
      language.capitalize
    end
  end

  def auto_codeql_language_color(language)
    linguist_name = case language
    when "c-cpp"
      "C"
    when "csharp"
      "C#"
    when "java-kotlin"
      "Java"
    when "javascript-typescript"
      "JavaScript"
    else
      language.capitalize
    end
    language_color(Linguist::Language[linguist_name])
  end
end
