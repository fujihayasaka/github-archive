# typed: true
# frozen_string_literal: true

class Api::CopilotWorkbench::Iteration < Api::App
  include FeatureFlagHelper

  before do
    deliver_error!(404) unless current_user&.spark_enabled?
  end

  before do
    # This endpoint is only supported from Codespaces, not from deployed Sparks
    checker = Api::Runtime::IntegrationChecker.new(
      current_user,
      current_integration,
      [:codespaces_production])

    return if checker.allowed?

    # Anything else is invalid, so let's error out
    deliver_error! 401, message: "Integration auth is not supported for this endpoint"
  end

  get "/copilot_workbench/:copilot_workbench_id/iterations/current", operation_id: :internal do
    @route_owner = "@github/copilot-workbench"

    control_access :copilot_workbench,
      resource: current_user,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    workbench = Spark::Workbench.for_uuid_string(current_user.id, params[:copilot_workbench_id])
    deliver_error!(404, message: "Workbench not found") unless workbench

    iteration = workbench.iterations.find_by(id: workbench.current_iteration_id)
    deliver_raw({ iteration: }, status: :ok)
  end

  post "/copilot_workbench/:copilot_workbench_id/iterations", operation_id: :internal do
    @route_owner = "@github/copilot-workbench"

    control_access :copilot_workbench,
      resource: current_user,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    workbench = Spark::Workbench.for_uuid_string(current_user.id, params[:copilot_workbench_id])
    deliver_error!(404, message: "Workbench not found") unless workbench

    iteration_params = receive(Hash, required: true)["iteration"]
    deliver_error!(400, message: "Bad request") unless iteration_params

    iteration_params = iteration_params.slice("prompt", "iteration_type", "sha", "suggestions", "files")
    iteration = Workbench::Iterations::Create.perform(workbench, iteration_params)
    deliver_error!(422, errors: iteration.errors) unless iteration.persisted?

    workbench.update(current_iteration_id: iteration.id)

    deliver_raw({ iteration: }, status: :created)
  end

  patch "/copilot_workbench/:copilot_workbench_id/iterations/:iteration_id", operation_id: :internal do
    @route_owner = "@github/copilot-workbench"

    control_access :copilot_workbench,
      resource: current_user,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    workbench = Spark::Workbench.for_uuid_string(current_user.id, params[:copilot_workbench_id])
    deliver_error!(404, message: "Workbench not found") unless workbench

    iteration = workbench.iterations.find_by(id: params[:iteration_id])
    deliver_error!(404, message: "Iteration not found") unless iteration

    iteration_params = receive(Hash, required: true)["iteration"]
    deliver_error!(400, message: "Bad request") unless iteration_params

    params = iteration_params.slice("prompt", "iteration_type", "sha", "suggestions")
    if iteration_params["files"]
      params["events"] = {
        files: iteration_params["files"]
      }
    end

    deliver_error!(422, errors: iteration.errors) unless iteration.update(params)

    deliver_raw({ iteration: }, status: :ok)
  end

  delete "/copilot_workbench/:copilot_workbench_id/iterations/:iteration_id", operation_id: :internal do
    @route_owner = "@github/copilot-workbench"

    control_access :copilot_workbench,
      resource: current_user,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    workbench = Spark::Workbench.for_uuid_string(current_user.id, params[:copilot_workbench_id])
    deliver_error!(404, message: "Workbench not found") unless workbench

    iteration = workbench.iterations.find_by(id: params[:iteration_id])
    deliver_error!(404, message: "Iteration not found") unless iteration

    iteration = Workbench::Iterations::Delete.perform(workbench, iteration)
    deliver_error!(422, errors: iteration.errors) if iteration.errors.present?

    deliver_empty(status: :no_content)
  end
end
