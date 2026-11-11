# typed: true
# frozen_string_literal: true

module Api::Serializer::ArtifactMetadataDependency
  extend T::Helpers
  requires_ancestor { Api::Serializer }
  requires_ancestor { Api::Serializer::RepositoriesDependency }

  def artifact_storage_records_hash(data, options = {})
    data[:records] ||= []
    record_hashes = data[:records].map do |record|
      artifact_storage_record_hash(record, options)
    end

    {
      total_count: data[:total_count],
      storage_records: record_hashes,
    }
  end

  sig { params(record: T.nilable(T.any(ArtifactStorageRecord, T::Hash[Symbol, T.untyped])), _options: T.untyped).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def artifact_storage_record_hash(record, _options = {})
    return nil unless record

    # The incoming record is either an ArtifactStorageRecord or a hash depending on the calling
    # endpoint. If it is an ArtifactStorageRecord, call the to_hash method and filter the hash for an API response
    hash = record.is_a?(ArtifactStorageRecord) ? record.to_hash : record
    {
      id: hash[:id],
      name: hash[:name],
      digest: hash[:digest],
      artifact_url: hash[:artifact_url],
      registry_url: hash[:registry_url],
      repository: hash[:registry_repository_name],
      status: hash[:status],
      created_at: hash[:created_at],
      updated_at: hash[:updated_at],
    }
  end

  def artifact_deployment_records_hash(data, options = {})
    data[:records] ||= []
    record_hashes = data[:records].map do |record|
      artifact_deployment_record_hash(record, options)
    end

    {
      total_count: data[:total_count],
      deployment_records: record_hashes,
    }
  end

  sig { params(record: T.nilable(T.any(ArtifactDeploymentRecord, T::Hash[Symbol, T.untyped])), _options: T.untyped).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def artifact_deployment_record_hash(record, _options = {})
    return nil unless record

    # The incoming record is either an ArtifactDeploymentRecord or a hash depending on the calling
    # endpoint. If it is an ArtifactDeploymentRecord, call the to_hash method and filter the hash for an API response
    hash = record.is_a?(ArtifactDeploymentRecord) ? record.to_hash : record
    {
      id: hash[:id],
      digest: hash[:digest],
      logical_environment: hash[:logical_environment],
      physical_environment: hash[:physical_environment],
      cluster: hash[:cluster],
      deployment_name: hash[:deployment_name],
      tags: hash[:custom_tags],
      runtime_risks: hash[:runtime_risks],
      created_at: hash[:created_at],
      updated_at: hash[:updated_at],
      attestation_id: hash[:attestation_id],
    }
  end
end
