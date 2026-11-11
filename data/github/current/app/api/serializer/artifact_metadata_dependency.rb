# typed: true
# frozen_string_literal: true

module Api::Serializer::ArtifactMetadataDependency
  extend T::Helpers
  requires_ancestor { Api::Serializer }
  requires_ancestor { Api::Serializer::RepositoriesDependency }

  def artifact_storage_records_hash(data, options = {})
    records = data[:records]
    if records.nil?
      return { total_count: data[:total_count] }
    end

    record_hashes = records.map do |record|
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
    records = data[:records]
    errors = data.fetch(:errors, nil)

    response = { total_count: data[:total_count] }

    # Include deployment_records in response only if records is not explicitly nil
    # When records is nil, it means return_records was false
    if !records.nil?
      record_hashes = if records.present?
        records.map { |record| artifact_deployment_record_hash(record, options) }
      else
        []
      end
      response[:deployment_records] = record_hashes
    end

    # Always serialize errors if they are present and non-empty
    if errors.present?
      error_hashes = errors.map do |error_entry|
        artifact_error_entry_hash(error_entry, options)
      end
      response[:errors] = error_hashes
    end

    response
  end

  sig { params(error_entry: T.nilable(T.any(ClusterDeploymentManager::ErrorEntry, T::Hash[Symbol, T.untyped])), _options: T.untyped).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def artifact_error_entry_hash(error_entry, _options = {})
    return nil unless error_entry

    # Handle both struct and hash representations
    if error_entry.is_a?(ClusterDeploymentManager::ErrorEntry)
      cause = error_entry.cause
      deployment = error_entry.deployment
      deployment_hash = {
        name: deployment.name,
        digest: deployment.digest,
        deployment_name: deployment.deployment_name,
        version: deployment.version,
        status: deployment.status,
        github_repository: deployment.github_repository,
        tags: deployment.tags,
        runtime_risks: deployment.runtime_risks,
      }
    else
      cause = error_entry[:cause]
      deployment_hash = error_entry[:deployment]
    end

    {
      cause: cause,
      deployment: deployment_hash,
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
