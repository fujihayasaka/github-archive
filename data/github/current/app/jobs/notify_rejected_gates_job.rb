# typed: true
# frozen_string_literal: true
require "github/launch_client"

class NotifyRejectedGatesJob < ApplicationJob
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  queue_as :actions

  def perform(gate_request_ids:, repository_global_relay_id:, gate_global_relay_id:)
    return unless GitHub.actions_enabled?

    GateRequest.where(id: gate_request_ids).find_each do |gate_request|
      next if gate_request.expires_at&.past? # expired gate requests will fail to notify gate because their authentication token has expired
      notify_gate(gate_request: gate_request, repository_global_relay_id: repository_global_relay_id, gate_global_relay_id: gate_global_relay_id)
    end
  end

  def notify_gate(gate_request:, repository_global_relay_id:, gate_global_relay_id:)
    check_run = gate_request.check_run
    check_suite = check_run.check_suite

    run_stamp_url = check_suite.workflow_run.latest_workflow_run_execution.run_stamp_url
    if run_stamp_url.present?
      request = GitHub::ActionsRunService::Api::Twirp::V1::NotifyGateRequest.new({
        gate_global_id: gate_global_relay_id,
        workflow_run_backend_id: check_suite.external_id,
        workflow_job_run_backend_id: check_run.external_id,
        is_open: false,
      })

      client = if ActionsRunService.is_lab_url?(run_stamp_url)
        ActionsRunService::Twirp::RunServiceLabClient.new(base_url: run_stamp_url)
      else
        ActionsRunService::Twirp::RunServiceClient.new(base_url: run_stamp_url)
      end
      result = client.notify_gate(request)
    else
      request = GitHub::Launch::Services::Environment::NotifyGateRequest.new({
        repository_id: GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: repository_global_relay_id),
        gate_id: GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: gate_global_relay_id),
        external_job_id: check_run.external_id,
        external_id: check_suite.external_id,
        is_open: false,
        token: gate_request.token,
        check_suite_id: GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: get_global_id(check_suite)),
      })

      if check_suite.github_app.launch_lab_github_app?
        Launch::Twirp::environment_lab_client.notify_gate(request)
      else
        Launch::Twirp::environment_client.notify_gate(request)
      end
    end
  end

  def get_global_id(entity)
    !GitHub.enterprise? ? entity.next_global_id : entity.global_relay_id
  end
end
