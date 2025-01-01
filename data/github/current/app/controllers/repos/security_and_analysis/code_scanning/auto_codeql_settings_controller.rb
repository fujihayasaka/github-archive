# typed: true
# frozen_string_literal: true

class Repos::SecurityAndAnalysis::CodeScanning::AutoCodeqlSettingsController < AbstractRepositoryController
  include DocsUrlHelper
  include Actions::RunnersHelper

  def self.react_bundle_name
    "repository-code-scanning-settings"
  end

  skip_before_action :privacy_check
  # added by Actions::RunnersHelper but we only use this to fetch runner labels
  skip_before_action :ensure_actions_enabled

  before_action :manage_security_products_permission_required
  before_action :writable_repository_required

  track_latency_slo "p99-ui-request", 3000, only: [:edit]
  track_latency_slo "p50-ui-request", 750, only: [:edit]

  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Iam,
    ApplicationRecord::Billing,
    ApplicationRecord::Memex,
    ApplicationRecord::RepositoriesActionsChecks,
    only: [:edit]

  depends_on_clusters ApplicationRecord::Copilot,
    optional: true,
    only: [:edit]

  def edit
    form_url = create_repository_auto_codeql_path
    form_method = :post

    if auto_codeql.enabled?
      form_url = update_repository_auto_codeql_path
      form_method = :put
    end

    add_csrf_token(form_url, form_method)

    available_runner_labels = if GitHub.actions_enabled?
      SecurityProductsEnablement::Actions::RunnerChecker.new(current_repository).labels
    else
      []
    end

    owner = current_repository.owner
    ghec = !!(owner.organization? && (owner.business || owner.business_plus?))

    render_react_app(
      payload: {
        formUrl: form_url,
        formMethod: form_method,
        isDefaultSetupEnabled: auto_codeql.enabled?,
        securityAnalysisUrl: repository_security_and_analysis_path(anchor: "code_scanning_settings"),
        querySuitesDocumentationUrl: docs_url("code-security/codeql-query-suites", ghec: ghec),
        taintedDataDocumentationUrl: docs_url("code-security/editing-your-configuration-of-default-setup", ghec: ghec, fragment: "including-local-sources-of-tainted-data-in-default-setup"),
        customBuildDocumentationUrl: docs_url("code-security/codeql-code-scanning-for-compiled-languages", ghec: ghec),
        codeqlLanguagesDocumentationUrl: docs_url("code-security/about-code-scanning-with-codeql", ghec: ghec, fragment: "about-codeql"),
        defaultBranch: current_repository.default_branch || "master",
        protectedBranchesUrl: edit_repository_branches_path(current_repository.owner, current_repository),
        selectableLanguages: selectable_languages,
        selectedLanguages: selected_languages,
        selectedQuerySuite: auto_codeql_configuration.query_suite || CodeScanning::AutoCodeql.recommended_query_suite(current_repository),
        recommendedQuerySuite: CodeScanning::AutoCodeql.recommended_query_suite(current_repository),
        querySuiteOptions: CodeScanning::AutoCodeql.query_suite_options(current_repository.owner),
        selectedThreatModel: auto_codeql_configuration.threat_model || auto_codeql.recommended_configuration.threat_model,
        showThreatModelInput: show_threat_model_input?,
        hasMacOsRunner: CodeScanning::Status.mac_os_runner?(repository: current_repository),
        nextScheduledRunAt: auto_codeql.next_scheduled_run_at,
        isRepoActive: auto_codeql.is_repo_active?,
        runnerLabel: auto_codeql_configuration.runner_label || auto_codeql.recommended_configuration.runner_label,
        onlyLabeledRunners: GitHub.enterprise?,
        availableRunnerLabels: [auto_codeql_configuration.runner_label.presence, *available_runner_labels].uniq.compact,
      },
      disable_ssr: true, # TODO: This was causing some issues with the generated DOM ids
      page_data: {
        selected_link: :security_analysis,
        title: "CodeQL default configuration"
      },
      layout: "layouts/settings/security_analysis",
    )
  end

  def create
    auto_codeql_options = auto_codeql_options_from_params
    can_enable = auto_codeql.can_enable?(actor: current_user, options: {
      runner_label: auto_codeql_options[:runner_label]
    })
    error_message = nil

    if can_enable.error?
      error_message = CodeScanning::AutoCodeql.error_to_message(can_enable.error)
    else
      auto_codeql_options[:action] = :enable
      result = SecurityProduct::ServiceManager.new(current_repository).toggle_services(T.must(current_user), services_to_enable: [[:auto_codeql, auto_codeql_options]])
      error_message = CodeScanning::AutoCodeql.error_to_message(result.error) if result.error?
    end

    if error_message.present?
      flash[:error] = error_message
    else
      flash[:notice] = "Repository settings saved. This initial setup might take a while because CodeQL will perform a full scan of the repository."
    end

    redirect_to repository_security_and_analysis_path
  end

  def update
    auto_codeql_options = auto_codeql_options_from_params
    can_enable = auto_codeql.can_enable?(actor: current_user, options: {
      runner_label: auto_codeql_options[:runner_label]
    })
    error_message = nil

    if can_enable.error?
      error_message = CodeScanning::AutoCodeql.error_to_message(can_enable.error)
    else
      auto_codeql_options[:action] = :update

      result = SecurityProduct::ServiceManager.new(current_repository).toggle_services(T.must(current_user), services_to_enable: [[:auto_codeql, auto_codeql_options]])
      error_message = "Failed to update code scanning default setup." if result.error?
    end

    if error_message.present?
      flash[:error] = error_message
    else
      unless T.must(result).result_for_service(:auto_codeql)[:noop]
        flash[:notice] = "Repository settings updated. This might take a while because CodeQL will perform a full scan of the repository."
      end
    end

    redirect_to repository_security_and_analysis_path
  end

  def destroy
    can_disable = auto_codeql.can_disable?(actor: current_user, options: {})
    error_message = nil

    if can_disable.error?
      error_message = CodeScanning::AutoCodeql.error_to_message(can_disable.error)
    else
      result = SecurityProduct::ServiceManager.new(current_repository).toggle_services(T.must(current_user), services_to_disable: [:auto_codeql])
      error_message = "Failed to disable code scanning default setup." if result.error?
    end

    if error_message.present?
      flash[:error] = error_message
    else
      flash[:notice] = "Repository settings saved. CodeQL is now disabled."

      if params[:switch] == "1"
        redirect_to helpers.code_scanning_codeql_template_url(current_repository)
        return
      end
    end

    redirect_to :back
  end

  def switch(from: params[:from].to_sym, to: params[:to].to_sym) # rubocop:disable GitHub/UseRestfulActions
    can_disable = auto_codeql.can_disable?(actor: current_user, options: {})

    if can_disable.error?
      error_message = CodeScanning::AutoCodeql.error_to_message(can_disable.error)
    else
      result = SecurityProduct::ServiceManager.new(current_repository).toggle_services(T.must(current_user), services_to_disable: [from], services_to_enable: [to])
      error_message = "Failed to switch between CodeQL setup types." if result.error?
    end

    if error_message.present?
      flash[:error] = error_message
    else
      flash[:notice] = "Repository settings saved. CodeQL setup type changed."
      flash[:notice] += " This initial setup might take a while because CodeQL will perform a full scan of the repository." if to == :auto_codeql
    end

    redirect_to :back
  end

  private

  def auto_codeql_options_from_params
    config_params = params.fetch(:config, {}).permit(:query_suite, :threat_model, :runner_type, :runner_label, :languages_selected, languages: [])

    languages = if ActiveModel::Type::Boolean.new.cast(config_params[:languages_selected])
      # if there is a selected language, it will always be populated, even if the languages did not change (only the query suite was edited)
      auto_codeql.language_support.canonical_names(config_params[:languages] || [])
    end

    query_suite = config_params.fetch(:query_suite, nil)
    threat_model = config_params.fetch(:threat_model, nil)
    runner_label = config_params.fetch(:runner_label, nil)
    runner_type  = config_params.fetch(:runner_type, nil)

    {}.tap do |options|
      options[:languages] = languages
      options[:query_suite] = query_suite if query_suite.present?
      options[:threat_model] = threat_model if threat_model.present?
      options[:runner_type] = runner_type if runner_type.present?
      options[:runner_label] = runner_label if runner_type == "labeled" && runner_label.present?
    end
  end

  def selectable_languages
    auto_codeql.language_support.supported_languages
  end

  def selected_languages
    # Preselect all supported languages when default setup is not enabled
    auto_codeql.enabled? ? auto_codeql_configuration.languages : auto_codeql.recommended_configuration.languages
  end

  def show_threat_model_input?
    selectable_languages.include?("java") ||
    selectable_languages.include?("java-kotlin") ||
    selectable_languages.include?("csharp")
  end

  memoize def auto_codeql_configuration
    auto_codeql.configuration
  end

  sig { returns(CodeScanning::AutoCodeql) }
  memoize def auto_codeql
    CodeScanning::AutoCodeql.new(current_repository)
  end
end
