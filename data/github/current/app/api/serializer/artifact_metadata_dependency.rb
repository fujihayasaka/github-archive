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

  def artifact_storage_record_hash(record, _options = {})
    return nil unless record

    {
      id: record.id,
      name: record.artifact_metadata.name,
      digest: record.artifact_metadata.digest,
      artifact_url: record.artifact_url,
      registry_url: record.registry_url,
      repository: record.registry_repository_name,
      status: record.artifact_metadata.status,
      created_at: record.created_at,
      updated_at: record.updated_at,
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

  def artifact_deployment_record_hash(record, _options = {})
    return nil unless record

    {
      id: record.id,
      digest: record.artifact_metadata.digest,
      logical_environment: record.logical_environment,
      physical_environment: record.physical_environment,
      cluster: record.cluster,
      deployment_name: record.deployment_name,
      tags: record.tags,
      created_at: record.created_at,
      updated_at: record.updated_at,
    }
  end
end
