# typed: true
# frozen_string_literal: true

class Api::RepositoryCodeQualitySetup < Api::App
  include Api::App::CodeScanningHelpers
  include Api::App::CodeQualityHelpers

  get "/repositories/:repository_id/code-quality/setup", operation_id: "code-quality/get-setup", read_from_replicas: true do
    repo = ActiveRecord::Base.connected_to(role: :reading) { find_repo! }

    control_access :manage_repo_code_quality_settings,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: repo.public?,
      forbid_message: "You are not authorized to read Code quality setup."

    if !CodeQuality.available?(repo)
      deliver_error! 404, message: "Code quality is not available for this repository."
    end

    enablement = CodeQualityEnablement.new(repo)

    configuration = if enablement.enabled?
      enablement.configuration
    else
      enablement.recommended_configuration_without_runner_labels
    end

    emit_analytics_event("read", repo.id, nil, nil)

    deliver :code_quality_setup_hash, configuration, repo: repo
  end

  patch "/repositories/:repository_id/code-quality/setup", operation_id: "code-quality/update-setup", read_from_replicas: true do
    repo = ActiveRecord::Base.connected_to(role: :reading) { find_repo! }

    control_access :manage_repo_code_quality_settings,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: repo.public?,
      forbid_message: "You are not authorized to update Code quality setup."

    if !CodeQuality.available?(repo)
      deliver_error! 404, message: "Code quality is not available for this repository."
    end

    deliver_error_if_archived!(repo)

    data = receive_with_openapi

    deliver_error! 422, message: "Invalid PATCH request with empty body." if data.empty?

    if data["state"] == "not-configured"
      disable!(repo)
    else
      enable_or_update!(repo, data)
    end
  end

  private

  sig { params(repo: Repository).void }
  def disable!(repo)
    service_mgr = SecurityProduct::ServiceManager.new(repo)

    result = service_mgr.toggle_services(current_user, services_to_disable: [[:code_quality, {
      feature: :CODE_QUALITY,
    }]])
    deliver_code_quality_error!(result.error) if result.error?

    emit_analytics_event("disable", repo.id, nil, nil)

    deliver_empty(status: 200)
  end

  sig { params(repo: Repository, data: T::Hash[String, T.untyped]).void }
  def enable_or_update!(repo, data)
    enablement = CodeQualityEnablement.new(repo)
    options = { action: enablement.enabled? ? :update : :enable }

    languages_to_enable = accept_languages_param!(repo, data["languages"])

    options[:languages] = languages_to_enable unless languages_to_enable.nil?
    options[:runner_type] = data["runner_type"] if data["runner_type"].present?
    options[:runner_label] = data["runner_label"] if data["runner_label"].present?
    options[:feature] = :CODE_QUALITY

    result = SecurityProduct::ServiceManager.new(repo).toggle_services(current_user, services_to_enable: [[:code_quality, options]])

    if result.error?
      exception = result.error
      if exception.is_a?(CodeScanning::AutoCodeqlError) && exception.twirp_error&.code == :already_exists
        deliver_error! 409, message: "Configuration update already in progress."
      end
      deliver_code_quality_error!(result.error)
    end

    updated_enablement = CodeQualityEnablement.new(repo)
    workflow_run_id = updated_enablement.get_actions_workflow_run_id
    deliver_error! 500 if workflow_run_id.nil?

    emit_analytics_event(options[:action].to_s, repo.id, options[:runner_type], options[:languages])

    deliver :code_scanning_default_setup_workflow_run_hash, workflow_run_id, repo:, status: 202
  end

  sig { params(error: T.untyped).void }
  def deliver_code_quality_error!(error)
    deliver_error! 422, message: CodeQualityEnablement.error_to_message(error)
  end

  sig { params(repository: Repository, request_languages: T.nilable(T::Array[String])).returns(T.nilable(T::Array[String])) }
  def accept_languages_param!(repository, request_languages)
    return if request_languages.nil?

    language_support = CodeScanning::ManagedAnalysesLanguageSupport.new(repository, :CODE_QUALITY)
    if language_support.non_repo_languages_present?(request_languages)
      deliver_error! 422, message: "One or more languages you selected are not present in the repository."
    end

    language_support.canonical_names(request_languages)
  end

  sig { params(action: String, repository_id: Integer, runner_type: T.nilable(String), languages: T.nilable(T::Array[String])).void }
  def emit_analytics_event(action, repository_id, runner_type, languages)
    parts = ["source:rest_api", "repository_id:#{repository_id}"]
    parts << "languages:#{languages.blank? ? "all" : languages.sort.join(",")}"
    parts << "runner_type:#{runner_type}" if runner_type.present?

    GlobalInstrumenter.instrument("analytics.event",
      action:,
      category: "code_quality",
      actor: current_user,
      label: parts.join(";"),
    )
  end
end
