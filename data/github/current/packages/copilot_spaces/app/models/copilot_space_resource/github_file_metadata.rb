# typed: true
# frozen_string_literal: true

class CopilotSpaceResource::GitHubFileMetadata < CopilotSpaceResource::Metadata
  attr_reader :repository_id, :repository, :file_path, :sha

  sig { override.params(json: T.untyped).returns(T.attached_class) }
  def self.from_json(json)
    new(
      repository_id: json["repository_id"],
      file_path: json["file_path"],
      sha: json["sha"],
    )
  end

  sig { params(repository_id: T.nilable(Integer), file_path: String, sha: T.nilable(String)).void }
  def initialize(repository_id:, file_path:, sha:)
    @repository_id = repository_id
    @file_path = file_path
    @sha = sha
    if @repository_id.present?
      @repository = Repositories::Public.find_active(@repository_id)
    end
  end

  sig do
    override
      .params(opts: T::Hash[Symbol, T.untyped])
      .returns(T.nilable(MonolithTwirp::Copilotapi::CustomCopilots::V1::GitHubFileMetadata))
  end
  def to_copilot_config_twirp(opts: { blob: nil, commit_oid: nil })
    return unless repository

    commit_oid = opts[:commit_oid] || repository.default_oid

    blob = opts[:blob]&.dig("data") || repository.blob(commit_oid, file_path, { truncate: false, limit: 128.kilobytes })&.data

    return unless blob

    if blob.dup.force_encoding("utf-8").valid_encoding?
      MonolithTwirp::Copilotapi::CustomCopilots::V1::GitHubFileMetadata.new(
        owner: repository.owner_display_login,
        name: repository.name,
        ref: sha || repository.default_branch, # For now we don't let the user pick the ref for the file unless it's provided via url dialog
        path: file_path,
        contents: blob,
        repo_id: repository.id,
        commit_oid: commit_oid,
        sha: commit_oid,
      )
    else
      GitHub.dogstats.increment("github.copilot.copilot_space.resource.encoding.invalid",  tags: ["encoding:#{blob.encoding.name}"])
      GitHub.logger.warn("Failed to enforce encoding", {
        "gh.copilot.copilot_space.file.encoding": blob.encoding.name,
      })
      nil
    end
  end

  sig { params(repository: Repository, file_resources: T::Array[CopilotSpaceResource]).returns(T::Array[MonolithTwirp::Copilotapi::CustomCopilots::V1::Resource]) }
  def self.batch_files_to_copilot_config_twirp(repository, file_resources)
    file_paths = file_resources.map(&:file_path)
    shas = file_resources.map(&:sha)
    default_repository_oid = repository.default_oid
    # Cache ref_to_sha results to avoid N+1 queries
    unique_shas = file_resources.map(&:sha).compact.uniq
    sha_to_commit_oid = unique_shas.each_with_object({}) do |sha, hash|
      hash[sha] = repository.ref_to_sha(sha)
    end

    sha_to_paths = file_resources.map do |resource|
      resolved_commit_oid = resource.sha ? (sha_to_commit_oid[resource.sha] || default_repository_oid) : default_repository_oid
      [resolved_commit_oid, resource.file_path]
    end

    # Fetch blob_oids
    blob_oids = repository.rpc.read_blob_oids(sha_to_paths, skip_bad: true)
    # Fetch blobs by blob_oid
    raw_blobs = repository.read_objects(blob_oids.select(&:present?), :blob)
    # Precompute a hash map for raw blobs by oid
    raw_blob_by_oid = raw_blobs.index_by { |raw_blob| raw_blob["oid"] }

    # create key for file paths with sha since file paths may not be unique
    # and we need to differentiate between files with the same path but different sha
    file_paths_with_sha = file_paths.zip(shas).map do |file_path, sha|
      sha ? "#{file_path}-#{sha}" : file_path
    end

    # Match blob_oids to file paths
    oids_by_blob_path = Hash[file_paths_with_sha.zip(blob_oids)]
    # Iterate over file resources and create twirp resource objects
    file_resources.filter_map do |file_resource|
      file_with_sha_key = file_resource.sha ? "#{file_resource.file_path}-#{file_resource.sha}" : file_resource.file_path
      blob_oid = oids_by_blob_path[file_with_sha_key]
      raw_blob = raw_blob_by_oid[blob_oid]
      resolved_commit_oid = sha_to_commit_oid[file_resource.sha] || default_repository_oid
      raw_blob && file_resource.twirp_resource(opts: { blob: raw_blob, commit_oid: resolved_commit_oid })
    end
  end

  sig { override.returns(T::Hash[Symbol, T.untyped]) }
  def to_url_validation_payload
    {
      type: CopilotSpaceResource::Constants::GITHUB_FILE,
      filePath: file_path,
      nwo: repository.name_with_display_owner,
      repositoryId: repository.id,
      fileExists: true,
      sha: sha || repository.default_branch,
    }
  end
end
