# typed: strict
# frozen_string_literal: true

require "react_payload"

class Repos::CodeQuality::SettingsController < AbstractRepositoryController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include CodeScanning::DefaultSetupHelper
  include Actions::RunnersHelper

  allow_verified_fetch only: [:update]

  before_action :login_required
  before_action :ensure_feature_code_quality_available
  before_action :manage_code_quality_permission_required
  before_action :writable_repository_required
  before_action :try_parse_json_params, only: [:update]

  # We only use this to fetch runner labels
  skip_before_action :ensure_actions_enabled

  class SettingsPayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "repoCodeQualitySettingsRoute"
    end

    sig do
      params(
        owner: String,
        repo: String,
        is_default_setup_enabled: T::Boolean,
        is_code_quality_enabled: T::Boolean,
        code_quality_setup_state: T.nilable(String),
        languages: T::Array[T::Hash[String, T.untyped]],
        default_branch: String,
        next_scheduled_run_at: T.nilable(Time),
        runner_label: T.nilable(String),
        about_codeql_docs_url: String,
        about_actions_billing_docs_url: String,
        codeql_languages_documentation_url: String,
        code_quality_docs_urls: T::Hash[String, String],
        has_mac_os_runner: T::Boolean,
        selectable_languages: T::Array[String],
        selected_languages: T::Array[String],
        settings_editable: T::Boolean,
        runner_type: String,
        only_labeled_runners: T::Boolean,
        available_runner_labels: T::Array[String],
        recent_activity_enabled: T::Boolean,
        is_enabling_allowed_by_policy: T::Boolean,
        code_quality_workflow_run_url: T.nilable(String),
        has_failed_update: T.nilable(T::Boolean),
        workflow_files: T::Array[T::Hash[String, String]],
        coverage_enabled: T::Boolean,
        coverage_agent_enabled: T::Boolean
      )
      .void
    end
    def initialize(
      owner:,
      repo:,
      is_default_setup_enabled:,
      is_code_quality_enabled:,
      code_quality_setup_state:,
      languages:, # TODO remove once RepoCodeQualitySettings.tsx includes LanguageSelection.tsx and code_quality_pass_feature_param is removed
      default_branch:,
      next_scheduled_run_at:,
      runner_label:,
      about_codeql_docs_url:,
      about_actions_billing_docs_url:,
      codeql_languages_documentation_url:,
      code_quality_docs_urls:,
      has_mac_os_runner:,
      selectable_languages:,
      selected_languages:,
      settings_editable:,
      runner_type:,
      only_labeled_runners:,
      available_runner_labels:,
      recent_activity_enabled:,
      is_enabling_allowed_by_policy:,
      code_quality_workflow_run_url:,
      has_failed_update:,
      workflow_files:,
      coverage_enabled:,
      coverage_agent_enabled:
    )
      @owner = T.let(owner, String)
      @repo = T.let(repo, String)
      @is_default_setup_enabled = T.let(is_default_setup_enabled, T::Boolean)
      @is_code_quality_enabled = T.let(is_code_quality_enabled, T::Boolean)
      @code_quality_setup_state = T.let(code_quality_setup_state, T.nilable(String))
      @languages = T.let(languages, T::Array[T::Hash[String, T.untyped]])
      @default_branch = T.let(default_branch, String)
      @next_scheduled_run_at = T.let(next_scheduled_run_at, T.nilable(Time))
      @runner_label = T.let(runner_label, T.nilable(String))
      @about_codeql_docs_url = T.let(about_codeql_docs_url, String)
      @about_actions_billing_docs_url = T.let(about_actions_billing_docs_url, String)
      @codeql_languages_documentation_url = T.let(codeql_languages_documentation_url, String)
      @code_quality_docs_urls = T.let(code_quality_docs_urls, T::Hash[String, String])
      @has_mac_os_runner = T.let(has_mac_os_runner, T::Boolean)
      @selectable_languages = T.let(selectable_languages, T::Array[String])
      @selected_languages = T.let(selected_languages, T::Array[String])
      @settings_editable = T.let(settings_editable, T::Boolean)
      @runner_type = T.let(runner_type, String)
      @only_labeled_runners = T.let(only_labeled_runners, T::Boolean)
      @available_runner_labels = T.let(available_runner_labels, T::Array[String])
      @recent_activity_enabled = T.let(recent_activity_enabled, T::Boolean)
      @is_enabling_allowed_by_policy = T.let(is_enabling_allowed_by_policy, T::Boolean)
      @code_quality_workflow_run_url = T.let(code_quality_workflow_run_url, T.nilable(String))
      @has_failed_update = T.let(has_failed_update, T.nilable(T::Boolean))
      @workflow_files = T.let(workflow_files, T::Array[T::Hash[String, String]])
      @coverage_enabled = T.let(coverage_enabled, T::Boolean)
      @coverage_agent_enabled = T.let(coverage_agent_enabled, T::Boolean)
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def payload
      payload = {
        owner: @owner,
        repo: @repo,
        isDefaultSetupEnabled: @is_default_setup_enabled,
        isCodeQualityEnabled: @is_code_quality_enabled,
        codeQualitySetupState: @code_quality_setup_state,
        languages: @languages,
        defaultBranch: @default_branch,
        nextScheduledRunAt: @next_scheduled_run_at,
        runnerLabel: @runner_label,
        aboutCodeQLDocsURL: @about_codeql_docs_url,
        aboutActionsBillingDocsURL: @about_actions_billing_docs_url,
        codeqlLanguagesDocumentationUrl: @codeql_languages_documentation_url,
        codeQualityDocsUrls: @code_quality_docs_urls,
        hasMacOsRunner: @has_mac_os_runner,
        selectableLanguages: @selectable_languages,
        selectedLanguages: @selected_languages,
        settingsEditable: @settings_editable,
        runnerType: @runner_type,
        onlyLabeledRunners: @only_labeled_runners,
        availableRunnerLabels: @available_runner_labels,
        recentActivityEnabled: @recent_activity_enabled,
        isEnablingAllowedByPolicy: @is_enabling_allowed_by_policy,
        codeQualityWorkflowRunUrl: @code_quality_workflow_run_url,
        workflowFiles: @workflow_files,
        coverageEnabled: @coverage_enabled,
        coverageAgentEnabled: @coverage_agent_enabled,
      }

      payload[:hasFailedUpdate] = @has_failed_update unless @has_failed_update.nil?
      payload
    end
  end

  # `update` does have dependencies too, but there aren't currently Rails tests for it
  # so we don't have a way of keeping that list up to date. Hence only declaring the
  # dependencies for `edit` here.
  depends_on_clusters ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesActionsChecks,
    only: [:edit]

  sig { void }
  def edit
    add_client_feature_flag([:cq_failed_status], entity: owner)
    respond_with_react(
      payload: payload,
      app_name: "code-quality",
      title: "Settings · Code quality · #{current_repository.name_with_display_owner}",
      page_data: {
        selected_link: :code_quality,
      },
      layout: "layouts/repository_settings",
    )
  end

  sig { void }
  def update
    manager = SecurityProduct::ServiceManager.new(current_repository)
    result = nil

    # This action is used for both enable/disable and changing settings
    # Where we're enabling/disabling, that happens via a specific AJAX
    # request with just `enabled` in the payload. So if we see that, we
    # know it's an enable/disable request and can ignore params relating
    # to updating settings.
    if params.has_key? :enabled
      result = if params[:enabled]
        manager.toggle_services(current_user, services_to_enable: [[:code_quality, { action: :enable }]])
      elsif params[:enabled] == false
        manager.toggle_services(current_user, services_to_disable: [:code_quality])
      end
    elsif params.has_key?(:config) && params[:config].has_key?(:languages)
      result = manager.toggle_services(current_user, services_to_enable: [[:code_quality, code_quality_options_from_params]])
    end

    CodeQualityEnablement.increment_enablement(metric: "request", tags: ["source:per_repo", "enabled:#{params[:enabled]}"])

    if result&.error?
      render json: { message: CodeQualityEnablement.error_to_message(result.error) }, status: :unprocessable_entity
    else
      response_payload = payload.payload.as_json
      render json: response_payload
    end
  end

  private

  # If some _non-policy_ error prevents toggling, this method will return true.
  # This is true even if there would also be a policy error, but the non-policy error
  # is the first one encountered (since `status` only holds a single error).
  sig { returns(T::Boolean) }
  def code_quality_toggle_allowed_by_policy?
    status = if code_quality_enablement.enabled?
      code_quality_enablement.can_disable?(actor: current_user, options: {})
    else
      code_quality_enablement.can_enable?(actor: current_user, options: {})
    end

    return true unless status.error?
    [
      :code_quality_not_allowed_by_policy,
      :code_quality_restricted_by_enablement_policy,
    ].exclude? status.error
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def code_quality_options_from_params
    config_params = params.fetch(:config, {}).permit(:runner_type, :runner_label, languages: [])

    runner_type = config_params.fetch(:runner_type, nil)
    runner_label = config_params.fetch(:runner_label, nil)

    {}.tap do |options|
      options[:action] = :update
      options[:languages] = config_params[:languages]
      options[:runner_type] = runner_type if runner_type.present?
      options[:runner_label] = runner_label if runner_type == "labeled" && runner_label.present?
    end
  end

  sig { returns(CodeQualityEnablement) }
  memoize def code_quality_enablement
    CodeQualityEnablement.new(current_repository)
  end

  sig { returns(CodeScanning::AutoCodeql) }
  memoize def auto_codeql
    CodeScanning::AutoCodeql.new(current_repository)
  end

  sig { returns(Repos::CodeQuality::SettingsController::SettingsPayload) }
  def payload
    ghec = !!(owner.organization? && (owner.business || owner.business_plus?))

    has_failed_update = if FeatureFlag.vexi.enabled?(:cq_failed_status, owner, default: false)
      code_quality_enablement.has_failed_update?
    end

    available_runner_labels = []

    enabling = code_quality_enablement.enabling?
    updating = !enabling && code_quality_enablement.updating?

    code_quality_setup_state = if enabling
      "enabling"
    elsif updating
      "updating"
    end

    SettingsPayload.new(
      owner: current_repository.owner.display_login,
      repo: current_repository.name,
      is_default_setup_enabled: true,
      is_code_quality_enabled: code_quality_enablement.enabled?,
      code_quality_setup_state: code_quality_setup_state,
      languages: code_quality_enablement.configuration.languages.map do |language|
        {
          name: auto_codeql_language_name(language),
          color: auto_codeql_language_color(language),
        }
      end,
      default_branch: current_repository.default_branch,
      next_scheduled_run_at: code_quality_enablement.next_scheduled_run_at,
      runner_label: code_quality_enablement.configuration.runner_label,
      about_codeql_docs_url: helpers.docs_url("code-security/about-code-scanning-with-codeql", fragment: "about-codeql"),
      about_actions_billing_docs_url: helpers.docs_url("billing/about-billing-for-github-actions"),
      codeql_languages_documentation_url: helpers.docs_url("code-security/about-code-scanning-with-codeql", ghec: ghec, fragment: "about-codeql"),
      code_quality_docs_urls: CodeQuality.code_quality_docs_urls,
      has_mac_os_runner: CodeScanning::Status.mac_os_runner?(repository: current_repository),
      selectable_languages: code_quality_enablement.language_support.supported_languages,
      selected_languages: code_quality_enablement.configuration.languages,
      # TODO Once all private preview customers have been transitioned to the new setup,
      # RepoCodeQualitySettings.tsx can be updated to always show the edit mode,
      # and this payload property can be removed.
      settings_editable: !code_quality_enablement.is_private_preview_config?,
      runner_type: code_quality_enablement.configuration.runner_type,
      only_labeled_runners: GitHub.enterprise?,
      available_runner_labels: [code_quality_enablement.configuration.runner_label.presence, *available_runner_labels].uniq.compact,
      recent_activity_enabled: CodeQuality.recent_activity_enabled?(current_repository),
      is_enabling_allowed_by_policy: code_quality_toggle_allowed_by_policy?,
      code_quality_workflow_run_url: code_quality_workflow_run_url,
      has_failed_update: has_failed_update,
      workflow_files: workflow_files,
      coverage_enabled: CodeCoverage.workflow_configuration_enabled?(current_repository),
      coverage_agent_enabled: CodeCoverage.coverage_agent_enabled?(current_repository),
    )
  end

  sig { returns(T.nilable(String)) }
  def code_quality_workflow_run_url
    return nil unless code_quality_actions_link_enabled?
    workflow_run_id = code_quality_enablement.get_actions_workflow_run_id
    return nil if workflow_run_id.nil? || workflow_run_id.zero?

    workflow_run_path(
      current_repository.owner,
      current_repository,
      workflow_run_id,
    )
  end

  sig { returns(T::Boolean) }
  def code_quality_actions_link_enabled?
    FeatureFlag.vexi.enabled?(:code_quality_actions_link, current_repository, current_repository.owner, default: false)
  end

  sig { returns(T::Array[T::Hash[String, String]]) }
  def workflow_files
    CodeQuality::WorkflowConfigLoader.new(repository: current_repository).workflow_files
  end

  # Technically this returns a nilable boolean, but you shouldn't use the return value
  sig { void }
  def ensure_feature_code_quality_available
    render_404 unless CodeQuality.available?(current_repository)
  end

  sig { void }
  def manage_code_quality_permission_required
    if current_repository.owner&.organization?
      render_access_denied unless CodeQualityManagementRepositoryPermissions.new(current_repository).code_quality_manageable_by?(current_user)
    else
      ensure_admin_access
    end
  end
end
