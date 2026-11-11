# typed: strict
# frozen_string_literal: true

class ArtifactRegistryHydroMessageManager
  # Deployment record events
  HYDRO_EVENT_CREATE_DEPLOYMENT_RECORD = "artifacts_metadata.artifact_deployment_record.create"
  HYDRO_EVENT_UPDATE_DEPLOYMENT_RECORD = "artifacts_metadata.artifact_deployment_record.update"
  HYDRO_EVENT_DELETE_DEPLOYMENT_RECORD = "artifacts_metadata.artifact_deployment_record.delete"
  # Storage record events
  HYDRO_EVENT_CREATE_STORAGE_RECORD = "artifacts_metadata.artifact_storage_record.create"
  HYDRO_EVENT_UPDATE_STORAGE_RECORD = "artifacts_metadata.artifact_storage_record.update"
  HYDRO_EVENT_DELETE_STORAGE_RECORD = "artifacts_metadata.artifact_storage_record.delete"

  sig { params(record: T::Hash[Symbol, T.untyped]).void }
  def self.send_hydro_message_for_deployment_record(record)
    event = if record[:deleted_at].present?
      HYDRO_EVENT_DELETE_DEPLOYMENT_RECORD
    elsif record[:created_at] == record[:updated_at]
      HYDRO_EVENT_CREATE_DEPLOYMENT_RECORD
    else
      HYDRO_EVENT_UPDATE_DEPLOYMENT_RECORD
    end

    send_hydro_message_for_deployment_record_by_event(event, record)
  end

  sig { params(event: String, record: T::Hash[Symbol, T.untyped]).void }
  def self.send_hydro_message_for_deployment_record_by_event(event, record)
    GlobalInstrumenter.instrument(event, {
      deployment_record_id: record[:id],
      attestation_id: record[:attestation_id],
      org_id: record[:org_id],
      repo_id: record[:repo_id],
      subject_digest: record[:digest],
    })
  end

  sig { params(records: T::Array[T::Hash[Symbol, T.untyped]]).void }
  def self.send_hydro_messages_for_storage_records(records)
    records.each do |record|
      event = case record[:status].to_s.downcase
      when ArtifactMetadata.statuses[:active].to_s.downcase
        HYDRO_EVENT_CREATE_STORAGE_RECORD
      when ArtifactMetadata.statuses[:eol].to_s.downcase
        HYDRO_EVENT_UPDATE_STORAGE_RECORD
      when ArtifactMetadata.statuses[:deleted].to_s.downcase
        HYDRO_EVENT_DELETE_STORAGE_RECORD
      end

      GlobalInstrumenter.instrument(event, {
        storage_record_id: record[:id],
        attestation_id: record[:attestation_id],
        org_id: record[:org_id],
        repo_id: record[:repo_id],
        subject_digest: record[:digest],
        actor_id: record[:actor_id],
        integration_id: record[:integration_id],
      })
    end
  end
end
