# typed: true
# frozen_string_literal: true

# Api::EnterpriseInstallationActionsJobExecutions are GitHub Connect endpoints for handling the export of
# of Actions Job Execution events from a GHES instance. These endpoints are split off from Api::EnterpriseInstallation
# so they can be owned by the Actions team.
class Api::EnterpriseInstallationActionsJobExecutions < Api::Enterprise::App
  before do
    deliver_error! 404 if GitHub.enterprise?
  end

  post "/enterprise-installation/usage-metrics/actions-job-executions", operation_id: :internal do
    @route_owner = "@github/actions-fusion-reviewers"
    require_enterprise_installation!

    control_access(:enterprise_usage_metrics,
      resource: current_enterprise_installation,
      allow_integrations: true,
      allow_user_via_granular_actor: false
    )

    # processing the list of actions job executions is best-effort. Therefore, we skip validation of the resource
    # and defer it to when the message is actually published to Hydro. This is to avoid situations where we reject
    # a request merely b/c a small subset of records are invalid
    data = receive_with_schema("enterprise-installation",
      "create-actions-job-executions",
      skip_validation: true)

    # Unfortunately, receive_with_schema doesn't allow us to skip validation for particular fields. Therefore, we
    # need to validate top-level fields manually
    validation_errors = []
    if !data.key?("server_id") || data["server_id"].empty?
      validation_errors << Api::EnterpriseInstallation::ServerIdNotValid.new("\"server_id\" must be provided")
    end

    if !data.key?("collected_at") || data["collected_at"].empty?
      validation_errors << Api::EnterpriseInstallation::CollectedAtNotValid.new("\"collected_at\" must be provided")
    end

    begin
      Time.iso8601(data["collected_at"])
    rescue ArgumentError
      validation_errors << Api::EnterpriseInstallation::CollectedAtNotValid.new("\"collected_at\" must be a valid ISO8601 timestamp")
    end

    if validation_errors.any?
      deliver_schema_validation_error!(ApiSchema::ValidationResult.new(validation_errors))
    end

    current_span = OpenTelemetry::Trace.current_span
    current_span.add_attributes({
      "ghes_server_id" => data["server_id"],
      "ghes_events_collected_at" => data["collected_at"]
      })

    # no-op if there's no list of actions job executions
    if !data.key?("job_executions") || data["job_executions"].empty?
      halt deliver_empty status: 204
    elsif data.key?("job_executions") && data["job_executions"].length > 10000
      deliver_error!(413, message: "The number of actions job executions exceeds the maximum allowed of 100000")
    end

    success_count = 0
    type_error_count = 0

    GitHub.logger.with_named_tags({
      "code.function": "publish_job_executions",
      "gh.ghes_server.id": data["server_id"],
      "gh.ghes_events.collected_at": data["collected_at"],
      "code.namespace": GitHub.context[:controller],
      #this doesn't seem to be in GitHub.context so pull it from the matched route
      "http.target": request.env["sinatra.route"],
      "http.method": GitHub.context[:request_method],
      "gh.request_id": GitHub.context[:request_id]
      }) do
      GitHub.logger.info({ "at" => "exec" })

      data["job_executions"].each do |job_execution|
        event = {
          server_id: data["server_id"],
          enterprise_installation: current_enterprise_installation,
          invoking_event_type: job_execution["invoking_event_type"],
          workflow_repository_id: job_execution["workflow_repository_id"],
          workflow_repository_global_id: job_execution["workflow_repository_global_id"],
          workflow_repository_visibility: job_execution["workflow_repository_visibility"],
          workflow_build_id: job_execution["workflow_build_id"],
          check_suite_id: job_execution["check_suite_id"],
          organization_id: job_execution["organization_id"],
          job_check_run_conclusion: job_execution["job_check_run_conclusion"],
          job_id: job_execution["job_id"],
          job_runtime: job_execution["job_runtime"],
          job_runtime_version: job_execution["job_runtime_version"],
          check_run_id: job_execution["check_run_id"],
          start_time: job_execution["start_time"],
          end_time: job_execution["end_time"],
          job_execution_billable_ms: job_execution["job_execution_billable_ms"],
          runner_properties: job_execution["runner_properties"],
          runner_type: job_execution["runner_type"],
        }

        begin
          GlobalInstrumenter.instrument("ghes_actions_job_execution.event", event)
          success_count += 1
        # Since we're delegating validation of job execution events to Hydro we need to catch all exceptions. This
        # handles the typical error cases (missing field types, wrong types, etc) as well as edge cases such as when the the item is not an object
        rescue => e # rubocop:disable Lint/GenericRescue
          GitHub.logger.warn("Failed to publish job execution event", e)
          type_error_count += 1
        end
      end
    end

    current_span.add_attributes({
      "job_execution_publish.total" => data["job_executions"].length,
      "job_execution_publish.success" => success_count,
      "job_execution_publish.errors" => type_error_count
    })

    # if the number of type errors is the same as the total number of job executions, then return a 400
    # indicating that all the data is bad and that the client should not retry the request. Partial failures
    # are treated as a success due to the best-effort nature of this endpoint
    if type_error_count == data["job_executions"].length
      deliver_error!(422, message: "All job execution events are invalid")
    else
      deliver_empty status: 204
    end
  end
end
