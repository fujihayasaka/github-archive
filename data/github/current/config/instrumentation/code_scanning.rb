# typed: true
# frozen_string_literal: true

GlobalInstrumenter.subscribe("pull_request.create") do |_event, _start, _ending, _transaction_id, payload|
  CodeScanning::PullRequestCreatedJob.perform_later(pull_request: payload[:pull_request])
end

GitHub.subscribe("workflow_run.status_changed") do |_event, _start, _ending, _transaction_id, payload|
  repository_id = payload[:repository_id]
  workflow_run_id = payload[:run_id]
  CodeScanning::AutoCodeqlSetRunConclusionJob.perform_later(repository_id:, workflow_run_id:)
end
