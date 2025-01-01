# typed: true
# frozen_string_literal: true

module Api::Serializer::ArtifactsDependency
  extend T::Helpers

  requires_ancestor { T.class_of(Api::Serializer) }

  # Creates a hash to be serialized to JSON.
  #
  # artifact - Artifact instance.
  # options  - Hash
  #
  # Returns a Hash if the Artifact exists, or nil.
  def artifact_hash(data, options = {})
    options = Api::SerializerOptions.from(options)
    artifact = data[:artifact]
    repository = data[:repository]
    workflow_run = data[:workflow_run]
    hash = simple_artifact_hash(artifact, repository, options)
    return hash if hash.nil?

    if artifact.check_suite.present? && artifact.check_suite.workflow_run.present?
      workflow_run ||= artifact.check_suite.workflow_run

      hash[:workflow_run] = {
        id: workflow_run.id,
        repository_id: artifact.check_suite.repository_id,
        head_repository_id: artifact.check_suite.head_repository_id,
        head_branch: artifact.check_suite.head_branch,
        head_sha: artifact.check_suite.head_sha,
      }
    else
      hash[:workflow_run] = nil
    end

    hash
  end

  # Creates a hash from a Artifact to be serialized to JSON. A short representation
  # suitable for sub-resources.
  #
  # artifact - Artifact instance
  #
  # Returns a Hash if the Artifact exists, or nil
  def simple_artifact_hash(artifact, repository, options = {})
    return nil unless artifact
    {
      id:            artifact.id,
      node_id:       global_id_for(artifact, options),
      name:          artifact.name,
      size_in_bytes: artifact.size,
      url:           url(artifact_path(artifact, repository, options)),
      archive_download_url:  url("#{artifact_path(artifact, repository, options)}/zip"),
      expired:       artifact.expired?,
      created_at:    time(artifact.created_at),
      updated_at:    time(artifact.updated_at),
      expires_at:    time(artifact.expires_at),
    }
  end

  def artifacts_hash(data, options = {})
    artifacts = data.fetch(:artifacts, [])
    repository = data[:repository]
    workflow_run = data[:workflow_run]
    artifacts_hashes = artifacts.map do |artifact|
      artifact_hash({ artifact: artifact, repository: repository, workflow_run: workflow_run }, options)
    end
    {}.tap do |h|
      h[:total_count] = data[:total_count]
      h[:artifacts] = artifacts_hashes
    end
  end

  private

  def artifact_path(artifact, repository, options = {})
    "/repos/#{repository.name_with_owner_for_api(use: options[:serialize_login])}/actions/artifacts/#{artifact.id}"
  end
end
