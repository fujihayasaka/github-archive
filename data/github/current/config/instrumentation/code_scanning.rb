# typed: true
# frozen_string_literal: true

GlobalInstrumenter.subscribe("pull_request.create") do |_event, _start, _ending, _transaction_id, payload|
  CodeScanning::PullRequestCreatedJob.perform_later(pull_request: payload[:pull_request])
end

GitHub.subscribe("workflow_run.status_changed") do |_event, _start, _ending, _transaction_id, payload|
  if payload[:action] == :completed || !FeatureFlag.vexi.enabled?(:code_scanning_enqueue_set_enabled_run_conclusion_only_on_completed, default: false)
    repository_id = payload[:repository_id]
    workflow_run_id = payload[:run_id]
    CodeScanning::AutoCodeqlSetRunConclusionJob.perform_later(repository_id:, workflow_run_id:)
  end
end
