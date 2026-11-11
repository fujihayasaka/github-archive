# typed: strict
# frozen_string_literal: true

class DeploymentTemplate
  class ArtifactLinkage
    sig { returns T.nilable(String) }
    attr_reader :github_repository

    sig { returns T.nilable(Integer) }
    attr_accessor :attestation_id
    sig { returns T.nilable(Integer) }
    attr_accessor :repository_id

    sig { returns T.nilable(T::Array[{ artifact_metadata_id: T.nilable(Integer), attestation_id: T.nilable(Integer), repository_id: Integer }]) }
    attr_accessor :repo_and_attestation_ids

    sig { params(github_repository: T.nilable(String)).void }
    def initialize(github_repository = nil)
      @github_repository = github_repository
    end

    sig { returns T::Boolean }
    def valid?
      ids = repo_and_attestation_ids
      return false if ids.blank?
      ids.any? { |entry| entry[:repository_id].present? }
    end
  end

  sig { returns ArtifactTemplate }
  attr_reader :artifact_template
  sig { returns String }
  attr_reader :cluster
  sig { returns String }
  attr_reader :deployment_name
  sig { returns String }
  attr_reader :logical_environment
  sig { returns Integer }
  attr_reader :owner_id
  sig { returns String }
  attr_reader :physical_environment
  sig { returns T::Array[String] }
  attr_reader :runtime_risks
  sig { returns T::Hash[Symbol, T.untyped] }
  attr_reader :tags
  sig { returns T.nilable(String) }
  attr_reader :github_repository
  sig { returns DeploymentTemplate::ArtifactLinkage }
  attr_accessor :linkage
  sig { returns String }
  attr_reader :status

  sig { params(owner_id: Integer, artifact_template: ArtifactTemplate, data: T::Hash[Symbol, T.untyped]).void }
  def initialize(owner_id, artifact_template, data)
    cluster = data[:cluster]
    deployment_name = data[:deployment_name]
    logical_environment = data[:logical_environment]
    physical_environment = data[:physical_environment] || ""
    runtime_risks = data[:runtime_risks] || []
    tags = data[:tags] || {}
    github_repository = data[:github_repository].presence
    status = data[:status] || "deployed"

    raise ArgumentError, "cluster is required" if cluster.blank?
    raise ArgumentError, "deployment_name is required" if deployment_name.blank?
    raise ArgumentError, "logical_environment is required" if logical_environment.blank?
    DeploymentRecordManager.validate_deployment_record_tags!(tags)

    @artifact_template = artifact_template
    @cluster = T.let(cluster, String)
    @deployment_name = T.let(deployment_name, String)
    @github_repository = T.let(github_repository, T.nilable(String))
    @logical_environment = T.let(logical_environment, String)
    @owner_id = owner_id
    @physical_environment = T.let(physical_environment, String)
    @runtime_risks = T.let(runtime_risks, T::Array[String])
    @tags = T.let(tags, T::Hash[Symbol, T.untyped])
    @linkage = T.let(ArtifactLinkage.new(github_repository), DeploymentTemplate::ArtifactLinkage)
    @status = T.let(status, String)
  end

  # Returns true if the template has artifact linkage information required to created deployment
  # records. Each template must have at least one repository and attestation ID pairing to create
  # or connect an existing artifact metadata record to a deployment record.
  sig { returns T::Boolean }
  def has_valid_artifact_linkage?
    @linkage.repo_and_attestation_ids.present?
  end

  sig { returns(T::Array[T::Hash[T.untyped, T.untyped]]) }
  def build_hashes_per_repo
    ids = @linkage.repo_and_attestation_ids
    return [] if ids.blank?

    now = Time.current

    ids.map do |entry|
      {
        artifact_metadata_id: entry[:artifact_metadata_id],
        cluster: @cluster,
        deployment_name: @deployment_name,
        logical_environment: @logical_environment,
        owner_id: @owner_id,
        physical_environment: @physical_environment,
        created_at: now,
        updated_at: now,
      }
    end
  end

  sig { params(existing_artifact_ids: T::Hash[[Integer, String], Integer], org_id: Integer, now: Time).returns(T::Array[T::Hash[T.untyped, T.untyped]]) }
  def build_artifact_metadata_inserts(existing_artifact_ids, org_id, now)
    inserts = []
    entries = @linkage.repo_and_attestation_ids
    digest = @artifact_template.digest
    return inserts if entries.blank? || digest.blank?
    entries.each do |entry|
      repository_id = entry[:repository_id]
      existing_id = existing_artifact_ids[[repository_id, digest]]
      if existing_id
        entry[:artifact_metadata_id] = existing_id
      else
        inserts << @artifact_template.to_hash.merge(
          repository_id: repository_id,
          owner_id: org_id,
          attestation_id: entry[:attestation_id],
          created_at: now,
          updated_at: now,
        )
      end
    end
    inserts
  end

  sig { params(all_artifact_ids: T::Hash[[Integer, String], Integer], org_id: Integer).void }
  def assign_artifact_metadata_ids!(all_artifact_ids, org_id)
    entries = @linkage.repo_and_attestation_ids
    return if entries.blank?

    digest = @artifact_template.digest
    entries.each do |entry|
      next if entry[:artifact_metadata_id].present?
      repository_id = entry[:repository_id]
      artifact_id = all_artifact_ids[[repository_id, digest]]
      if artifact_id.nil?
        GitHub.logger.error("Failed to find artifact metadata record for repository_id #{repository_id}" \
          " and digest #{digest} after bulk insert, cannot create deployment record", "gh.org.id" => org_id, "repository_id" => repository_id, "digest" => digest)
        next
      end
      entry[:artifact_metadata_id] = artifact_id
    end
  end

  sig { params(deployment_record_id: Integer, now: Time).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def build_tag_inserts(deployment_record_id, now)
    return [] if @tags.blank? && @runtime_risks.blank?

    tag_rows = []
    @tags.each do |k, v|
      tag_rows << { deployment_record_id: deployment_record_id, tag_name: k.to_s, tag_value: v.to_s, created_at: now, updated_at: now }
    end
    @runtime_risks.each do |risk|
      tag_rows << { deployment_record_id: deployment_record_id, tag_name: "runtime-risk", tag_value: risk, created_at: now, updated_at: now }
    end
    tag_rows
  end
end
