# typed: true
# frozen_string_literal: true

module Api::Serializer::RepositoryDependencyGraphSnapshot
  def repository_snapshot_create_hash(snapshot_create_response, options = {})
    {
      id: snapshot_create_response.snapshot_id,
      created_at: snapshot_create_response.created_at.present? ? snapshot_create_response.created_at.to_time.utc : nil,
      result: snapshot_create_response.result,
      message: snapshot_create_response.message,
    }
  end

  def repository_snapshot_hash(snapshot_get_response, options = {})
    return {} unless snapshot_get_response.payload.present?

    {
      snapshot_id: snapshot_get_response.snapshot_id,
      repository_id: snapshot_get_response.repository_id,
      snapshot: JSON.parse(snapshot_get_response.payload)
    }
  end

  def dependencies_hash(dependencies_get_response, options = {})
    return {} unless dependencies_get_response.manifests.present?

    {
      dependencies: dependencies_get_response.manifests.map { |m| m.to_h }
    }
  end

  def repository_snapshot_diff_hash(snapshot_diff_hash, options = {})
    base_snapshot = snapshot_diff_hash[:base_snapshot]
    target_snapshot = snapshot_diff_hash[:target_snapshot]

    {
      base_snapshot: {
        sha: base_snapshot[:sha],
        snapshot_id: base_snapshot[:snapshot_id],
        metadata: base_snapshot[:metadata]
      },
      target_snapshot: {
        sha: target_snapshot[:sha],
        snapshot_id: target_snapshot[:snapshot_id],
        metadata: target_snapshot[:metadata]
      },
      changed_manifests: snapshot_diff_hash[:changed_manifests]&.map { |m| m.to_h },
      vulnerable_dependencies: snapshot_diff_hash[:vulnerable_dependencies],
      dependency_metadata: snapshot_diff_hash[:dependency_metadata]
    }
  end
end
