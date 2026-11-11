# typed: true
# frozen_string_literal: true

# Subscribe to artifact metadata events to enqueue system property updates.
# When storage or deployment records are created, updated, or deleted, we
# enqueue a background job to recompute the `deployable` and `deployed`
# system properties for the affected repository.
%w[
  artifacts_metadata.artifact_storage_record.create
  artifacts_metadata.artifact_storage_record.update
  artifacts_metadata.artifact_storage_record.delete
  artifacts_metadata.artifact_deployment_record.create
  artifacts_metadata.artifact_deployment_record.update
  artifacts_metadata.artifact_deployment_record.delete
].each do |event_name|
  GlobalInstrumenter.subscribe(event_name) do |event|
    repo_id = event.payload[:repo_id]
    UpdateRepositoryDeploymentPropertiesJob.perform_later(repo_id) if repo_id.present?
  end
end
