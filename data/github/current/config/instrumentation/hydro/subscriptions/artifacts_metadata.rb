# typed: true
# frozen_string_literal: true

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("artifacts_metadata.artifact_storage_record.create") do |payload|
    message = {
        storage_record_id: payload[:storage_record_id],
        org_id: payload[:org_id],
        repo_id: payload[:repo_id],
        subject_digest: payload[:subject_digest],
        attestation_id: payload[:attestation_id]
    }

    publish(message, schema: "github.artifacts_metadata.v0.CreateStorageRecord")
  end

  subscribe("artifacts_metadata.artifact_storage_record.update") do |payload|
    message = {
        storage_record_id: payload[:storage_record_id],
        org_id: payload[:org_id],
        repo_id: payload[:repo_id],
        subject_digest: payload[:subject_digest],
        attestation_id: payload[:attestation_id]
    }

    publish(message, schema: "github.artifacts_metadata.v0.UpdateStorageRecord")
  end

  subscribe("artifacts_metadata.artifact_storage_record.delete") do |payload|
    message = {
        storage_record_id: payload[:storage_record_id],
        org_id: payload[:org_id],
        repo_id: payload[:repo_id],
        subject_digest: payload[:subject_digest],
        attestation_id: payload[:attestation_id]
    }

    publish(message, schema: "github.artifacts_metadata.v0.DeleteStorageRecord")
  end

  subscribe("artifacts_metadata.artifact_deployment_record.create") do |payload|
    message = {
        deployment_record_id: payload[:deployment_record_id],
        org_id: payload[:org_id],
        repo_id: payload[:repo_id],
        subject_digest: payload[:subject_digest],
        attestation_id: payload[:attestation_id]
    }

    publish(message, schema: "github.artifacts_metadata.v0.CreateDeploymentRecord")
  end

  subscribe("artifacts_metadata.artifact_deployment_record.update") do |payload|
    message = {
        deployment_record_id: payload[:deployment_record_id],
        org_id: payload[:org_id],
        repo_id: payload[:repo_id],
        subject_digest: payload[:subject_digest],
        attestation_id: payload[:attestation_id]
    }

    publish(message, schema: "github.artifacts_metadata.v0.UpdateDeploymentRecord")
  end

  subscribe("artifacts_metadata.artifact_deployment_record.delete") do |payload|
    message = {
        deployment_record_id: payload[:deployment_record_id],
        org_id: payload[:org_id],
        repo_id: payload[:repo_id],
        subject_digest: payload[:subject_digest],
        attestation_id: payload[:attestation_id]
    }

    publish(message, schema: "github.artifacts_metadata.v0.DeleteDeploymentRecord")
  end
end
