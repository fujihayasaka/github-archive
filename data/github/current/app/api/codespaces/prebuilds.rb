# typed: true
# frozen_string_literal: true

class Api::Codespaces::Prebuilds < Api::Codespaces
  CODESPACES_NOT_ENABLED_MESSAGE = "Codespaces are not enabled"
  MISSING_PAT_SECRET_KEY = "The codespaces secret \"#{::Codespaces::GetPrebuildSecrets::PREBUILD_PAT_SECRET_KEY}\" must be set."
  TEMPLATE_LOGS_NOT_FOUND_MESSAGE = "Prebuild Template logs not found"
  MISSING_VSCS_TARGET_URL = "VSCS target URL is required when running locally"
  FORBIDDEN_VSCS_TARGET_URL = "VSCS target URL must only be provided when running locally"
  FEATURE_NOT_SUPPORTED_MESSAGE = "This feature not supported for this repository"
  INVALID_SKU_NAME = "Invalid sku_name"
  BAD_RESPONSE_MESSAGE = "Bad response"
  CONNECTION_ERROR_MESSAGE = "Connection Error"
  AGENT_DOWNLOAD_URL_NOT_FOUND_MESSAGE = "Agent download URL not found"
  MISSING_LOCATION = "Location is required"
  MISSING_WORKFLOW_RUN_ID = "Workflow run id is required"
  INVALID_TEMPLATE_INFO = "Invalid template info"
  INVALID_WORKFLOW_RUN = "Invalid workflow_run"
  TEMPLATE_NOT_FOUND_MESSAGE = "Prebuild template not found"

  post "/codespaces_internal/prebuilds/repository/:repository_id/templates", operation_id: :internal do
    with_aggressive_client_timeouts do
      @route_owner = "@github/codespaces"
      deliver_prebuild_template_error! 404, message: CODESPACES_NOT_ENABLED_MESSAGE unless GitHub.codespaces_enabled?

      data = receive_with_schema("codespace", "codespaces-prebuild-template-with-workflow", expected_type: Hash)
      vscs_target, location, vscs_target_url, workflow_run_id, configuration_id, environment_options = data.values_at(
          "vscs_target", "location", "vscs_target_url", "workflow_run_id", "configuration_id",  "environment_options"
      )

      workflow_run = validate_workflow_run!(workflow_run_id: workflow_run_id, repo: current_repo)
      control_access :prebuild_codespaces,
        resource: workflow_run,
        allow_integrations: true,
        allow_user_via_granular_actor: false

      unless current_repo&.owner.codespaces_feature_enabled?
        deliver_prebuild_template_error! 403, message: FEATURE_NOT_SUPPORTED_MESSAGE
      end

      branch = workflow_run.head_branch
      oid = workflow_run.head_sha
      vscs_target = vscs_target&.to_sym || Codespaces::Vscs.default_target
      template_info = environment_options["template_info"]
      deliver_prebuild_template_error! 400, message: INVALID_TEMPLATE_INFO unless template_info["template_size"] > 0

      prebuild_template_fields = {
        repository: current_repo,
        vscs_target: vscs_target,
        vscs_target_url: vscs_target_url,
        location: location,
        oid: oid,
        branch: branch,
        environment_options: environment_options,
        workflow_run_id: workflow_run_id,
        configuration_id: configuration_id
      }

      begin
        template, storage_sas_url = Codespaces::CreatePrebuildTemplate.call(**prebuild_template_fields)

        success_response = build_prebuild_template_response(template: template)
        success_response[:storage_sas_url] = storage_sas_url
        deliver_raw success_response, status: 200
      rescue Codespaces::CreatePrebuildTemplate::FeatureNotSupported => e
        deliver_prebuild_template_error! 403, message: e.message
      rescue Codespaces::CreatePrebuildTemplate::InvalidPrebuildTemplate => e
        deliver_prebuild_template_error! 400, message: e.message
      rescue Codespaces::ValidatePrebuildAccess::AuthorizationError => e
        deliver_prebuild_template_error! 403, message: e.message
      rescue Codespaces::ValidatePrebuildAccess::CreationCircuitBreaker => e
        deliver_prebuild_template_error! 503, message: e.message
      end
    end
  end

  patch "/codespaces_internal/prebuilds/repository/:repository_id/templates/:guid", operation_id: :internal do
    with_aggressive_client_timeouts do
      @route_owner = "@github/codespaces"
      deliver_prebuild_template_error! 404, message: CODESPACES_NOT_ENABLED_MESSAGE unless GitHub.codespaces_enabled?

      data = receive_with_schema("codespace", "codespaces-prebuild-template-update", expected_type: Hash)
      state, workflow_run_id = data.values_at(
        "state", "workflow_run_id"
      )

      workflow_run = validate_workflow_run!(workflow_run_id: workflow_run_id, repo: current_repo)
      control_access :prebuild_codespaces,
        resource: workflow_run,
        allow_integrations: true,
        allow_user_via_granular_actor: false

      unless current_repo&.owner.codespaces_feature_enabled?
        deliver_prebuild_template_error! 403, message: FEATURE_NOT_SUPPORTED_MESSAGE
      end

      prebuild_template = Codespaces::PrebuildTemplate.find_by(guid: params[:guid], repository: current_repo)
      deliver_prebuild_template_error! 404, message: TEMPLATE_NOT_FOUND_MESSAGE unless prebuild_template.present?

      validate_workflow_run!(workflow_run_id: workflow_run_id, repo: current_repo)

      begin
        Codespaces::ValidatePrebuildAccess.call(repository: current_repo, vscs_target: prebuild_template&.vscs_target, vscs_target_url: prebuild_template&.vscs_target_url)
      rescue Codespaces::ValidatePrebuildAccess::AuthorizationError => e
        deliver_prebuild_template_error! 403, message: e.message
      rescue Codespaces::ValidatePrebuildAccess::CreationCircuitBreaker => e
        deliver_prebuild_template_error! 503, message: e.message
      end

      begin
        template = Codespaces::UpdatePrebuildTemplate.call(guid: params[:guid], repository: current_repo, state: state)

        success_response = build_prebuild_template_response(template: template)
        deliver_raw success_response, status: 200
      rescue Codespaces::UpdatePrebuildTemplate::BadResponse
        deliver_prebuild_template_error! 400, message: BAD_RESPONSE_MESSAGE
      rescue Codespaces::UpdatePrebuildTemplate::ConnectionFailed
        deliver_prebuild_template_error! 408, message: CONNECTION_ERROR_MESSAGE
      rescue Codespaces::UpdatePrebuildTemplate::InvalidTemplateState => e
        deliver_prebuild_template_error! 400, message: e.message
      end
    end
  end

  get "/codespaces_internal/prebuilds/repository/:repository_id/agent/download", operation_id: :internal do
    with_aggressive_client_timeouts do
      @route_owner = "@github/codespaces"

      vscs_target, vscs_target_url, location, workflow_run_id = params.values_at(
        "vscs_target", "vscs_target_url", "vscs_location", "workflow_run_id"
      )

      deliver_prebuild_template_error! 400, message: MISSING_WORKFLOW_RUN_ID unless workflow_run_id.present?

      workflow_run = validate_workflow_run!(workflow_run_id: workflow_run_id, repo: current_repo)

      control_access :prebuild_codespaces,
        resource: workflow_run,
        allow_integrations: true,
        allow_user_via_granular_actor: false

      vscs_target = vscs_target&.to_sym || Codespaces::Vscs.default_target
      deliver_prebuild_template_error! 400, message: MISSING_LOCATION unless location.present?
      begin
        Codespaces::ValidatePrebuildAccess.call(repository: current_repo, vscs_target: vscs_target, vscs_target_url: vscs_target_url)
      rescue Codespaces::ValidatePrebuildAccess::AuthorizationError => e
        deliver_prebuild_template_error! 403, message: e.message
      rescue Codespaces::ValidatePrebuildAccess::CreationCircuitBreaker => e
        deliver_prebuild_template_error! 503, message: e.message
      end


      begin
        agent_download_url = Codespaces::GetAgentDownloadUrl.call(location: location, vscs_target: vscs_target, vscs_target_url: vscs_target_url)
        redirect agent_download_url
      rescue Codespaces::GetAgentDownloadUrl::ConnectionFailed
        deliver_prebuild_template_error! 408, message: CONNECTION_ERROR_MESSAGE
      rescue Codespaces::GetAgentDownloadUrl::BadResponse
        deliver_prebuild_template_error! 400, message: BAD_RESPONSE_MESSAGE
      rescue Codespaces::GetAgentDownloadUrl::AgentDownloadUriNotFound
        deliver_prebuild_template_error! 404, message: AGENT_DOWNLOAD_URL_NOT_FOUND_MESSAGE
      end
    end
  end

  post "/codespaces_internal/prebuilds/repository/:repository_id/agent/diagnostics", operation_id: :internal do
    with_aggressive_client_timeouts do
      @route_owner = "@github/codespaces"

      workflow_run_id = env["HTTP_WORKFLOW_RUN_ID"]
      deliver_prebuild_template_error! 400, message: MISSING_WORKFLOW_RUN_ID unless workflow_run_id.present?

      workflow_run = validate_workflow_run!(workflow_run_id: workflow_run_id, repo: current_repo)

      control_access :prebuild_codespaces,
        resource: workflow_run,
        allow_integrations: true,
        allow_user_via_granular_actor: false

      # Forward to EastUs to emit to the region with closest proximity to data centers
      # Set target to prod because logging is tied to prod dotcom action runs
      location = Codespaces::Locations::Region.find("EastUs").id
      vscs_target = Codespaces::Vscs.default_target

      begin
        Codespaces::ValidatePrebuildAccess.call(repository: current_repo, vscs_target: vscs_target)
      rescue Codespaces::ValidatePrebuildAccess::AuthorizationError => e
        deliver_prebuild_template_error! 403, message: e.message
      rescue Codespaces::ValidatePrebuildAccess::CreationCircuitBreaker => e
        deliver_prebuild_template_error! 503, message: e.message
      end

      validate_workflow_run!(workflow_run_id: workflow_run_id, repo: current_repo)
      telemetry_data = JSON.parse(request.body.read)

      begin
        Codespaces::SendAgentTelemetry.call(telemetry_json: telemetry_data.to_json, location: location, vscs_target: vscs_target)
      rescue Codespaces::SendAgentTelemetry::ConnectionFailed
        deliver_prebuild_template_error! 408, message: CONNECTION_ERROR_MESSAGE
      rescue Codespaces::SendAgentTelemetry::BadResponse
        deliver_prebuild_template_error! 400, message: BAD_RESPONSE_MESSAGE
      end
    end
  end

  private

  def deliver_prebuild_template_error!(status, message:)
    deliver_error!(status, message: "Error: #{message}")
  end

  def validate_workflow_run!(workflow_run_id:, repo:)
    workflow_run = Actions::WorkflowRun.find_by(id: workflow_run_id)
    unless workflow_run.present? && workflow_run.repository_id == repo.id && workflow_run.status != "completed"
      deliver_prebuild_template_error! 400, message: INVALID_WORKFLOW_RUN
    end
    workflow_run
  end

  def build_prebuild_template_response(template:)
    {
      template: {
        id: template.id,
        location: template.location,
        branch: template.branch,
        state: template.state,
        guid: template.guid,
      }
    }
  end
end
