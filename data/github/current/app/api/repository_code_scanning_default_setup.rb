# typed: true
# frozen_string_literal: true

class Api::RepositoryCodeScanningDefaultSetup < Api::App
  include Api::App::CodeScanningHelpers

  get "/repositories/:repository_id/code-scanning/default-setup", operation_id: "code-scanning/get-default-setup" do
    repo = ActiveRecord::Base.connected_to(role: :reading) { find_repo! }
    ensure_read_access_and_code_scanning_enabled!(repo, forbid: repo.public?)
    control_access :view_repo_security_products,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: "You are not authorized to read code scanning default setup."

    auto_codeql = CodeScanning::AutoCodeql.new(repo)

    configuration = auto_codeql.enabled? ? auto_codeql.configuration : auto_codeql.recommended_configuration_without_runner_labels

    if changeset_active?(:remove_single_js_ts)
      deliver :code_scanning_default_setup_hash, configuration, repo: repo
    else
      deliver :code_scanning_default_setup_including_single_js_ts_hash, configuration, repo: repo
    end
  end

  patch "/repositories/:repository_id/code-scanning/default-setup", operation_id: "code-scanning/update-default-setup" do
    repo = ActiveRecord::Base.connected_to(role: :reading) { find_repo! }
    ensure_read_access_and_code_scanning_enabled!(repo, forbid: repo.public?)

    control_access :manage_repo_security_products,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: "You are not authorized to update Code scanning default setup."

    deliver_error_if_archived!(repo)

    data = receive_with_openapi

    deliver_error! 422, message: "Invalid PATCH request with empty body." if data.empty?

    auto_codeql = CodeScanning::AutoCodeql.new(repo)
    if data["state"] == "not-configured"
      # Disabling default setup can be done independently of the current state.
      disable(auto_codeql)
    else
      enable_or_update(auto_codeql, data)
    end
  end

  patch "/repositories/:repository_id/code-scanning/default-setup/adjust", operation_id: "code-scanning/adjust-default-setup" do
    repo = ActiveRecord::Base.connected_to(role: :reading) { find_repo! }
    ensure_read_access_and_code_scanning_enabled!(repo, forbid: repo.public?)

    control_access :write_code_scanning,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: "You are not authorized to adjust Code scanning default setup configuration."

    deliver_error_if_archived!(repo)

    data = receive_with_openapi

    languages = T.let(data["languages"], T::Array[String])
    if languages.blank?
      deliver_error! 422, message: "Languages have to be present."
    end

    run_id = T.let(data["workflow_run_id"], T.nilable(Integer)) if data["workflow_run_id"].present?

    result = CodeScanning::AutoCodeql.new(repo).adjust_configuration(languages, run_id)
    if result.error?
      exception = result.error
      if exception.is_a?(CodeScanning::AutoCodeqlError)
        if exception.twirp_error&.code == :failed_precondition && exception.twirp_error&.msg == "wrong workflow run"
          deliver_error! 409, message: "The configuration being validated by the workflow has already been superseded."
        elsif exception.twirp_error&.code == :failed_precondition && exception.twirp_error&.msg == "repository is not onboarding"
          deliver_error! 409, message: "Adjustment of the configuration being validated by the workflow is not possible anymore."
        end
      end
      deliver_error! 422, message: "Failed to adjust configuration"
    end

    deliver_empty(status: 202)
  end

  private

  def disable(auto_codeql)
    service_mgr = SecurityProduct::ServiceManager.new(auto_codeql.repository)
    result = service_mgr.toggle_services(current_user, services_to_disable: [:auto_codeql])
    deliver_auto_codeql_error!(result.error) if result.error?

    deliver_empty(status: 200)
  end

  def enable_or_update(auto_codeql, data)
    options = { action: auto_codeql.disabled? ? :enable : :update }
    deliver_error! 422, message: "Repository is currently not configured for default setup." if options[:action] == :enable && data["state"] != "configured"
    repository = auto_codeql.repository
    languages_to_enable = accept_languages_param(repository, data["languages"])

    options[:languages] = languages_to_enable unless languages_to_enable.nil?
    options[:query_suite] = data["query_suite"] if data["query_suite"].present?
    options[:runner_type] = data["runner_type"] if data["runner_type"].present?
    options[:runner_label] = data["runner_label"] if data["runner_label"].present?
    options[:threat_model] = data["threat_model"] if data["threat_model"].present?

    result = SecurityProduct::ServiceManager.new(repository).toggle_services(current_user, services_to_enable: [[:auto_codeql, options]])

    if result.error?
      exception = result.error
      if exception.is_a?(CodeScanning::AutoCodeqlError) && exception.twirp_error&.code == :already_exists
        deliver_error! 409, message: "Configuration update already in progress."
      end
      deliver_auto_codeql_error!(result.error)
    end

    deliver_error! 500 if result.result_for_service(:auto_codeql).empty?
    workflow_run_id = result.result_for_service(:auto_codeql)[:workflow_run_id]

    deliver :code_scanning_default_setup_workflow_run_hash, workflow_run_id, repo: auto_codeql.repository, status: 202
  end

  def deliver_auto_codeql_error!(error)
    deliver_error! 422, message: CodeScanning::AutoCodeql.error_to_message(error)
  end

  def accept_languages_param(repository, request_languages)
    return if request_languages.nil?

    language_support = CodeScanning::AutoCodeqlLanguageSupport.new(repository)
    if language_support.non_repo_languages_present?(request_languages)
      deliver_error! 422, message: "One or more languages you selected are not present in the repository."
    end

    language_support.canonical_names(request_languages)
  end
end
