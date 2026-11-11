# typed: true
# frozen_string_literal: true

class DeploymentRecordManager
  class ErrConflictingDeploymentInfo < StandardError
    attr_reader :digest, :name, :version, :found_name, :found_version

    def initialize(digest, name, version, found_name, found_version)
      @digest = digest
      @name = name
      @version = version
      @found_name = found_name
      @found_version = found_version
      super("Conflicting deployment info for digest #{digest}: (#{found_name}, #{found_version}) vs (#{name}, #{version})")
    end
  end

  class ErrDuplicateDeploymentName < StandardError
    def initialize
      super("Duplicate deployment_name found. Each deployment must have a unique deployment_name.")
    end
  end

  class ErrInvalidTag < StandardError
    attr_reader :key

    def initialize(key)
      @key = key
      super("Invalid tag: #{key}. Custom tags cannot begin with runtime risk")
    end
  end

  def categorize_cluster_deployment_changes(current_records)
    # Create a hash of current records for easy lookup by deployment_name
    # This will be used to determine which records need to be updated, created, or deleted
    current_records_by_deployment_name = current_records.each_with_object({}) do |record, hash|
      hash[record.deployment_name] = record
    end

    if deployment_templates.blank?
      # If there are no incoming deployment templates, then all existing records should be deleted
      return { to_create: [], to_update: [], to_delete: current_records }
    end

    to_update = []
    to_create = []
    deployments = deployment_templates.values.flatten
    deployments.each do |deployment|
      # If a deployment template does not have valid artifact linkage, skip it as it should be processed by the endpoint.
      next if !deployment.has_valid_artifact_linkage?

      deployment_name = deployment.deployment_name
      # Because we have already looked up existing records by cluster, logical_environment, and physical_environment,
      # we only need to check whether the deployment_name of a new proposed record matches an existing record in the hash
      existing_record = current_records_by_deployment_name[deployment_name]

      if existing_record
        to_update << deployment
        # delete the hash entry as we have already claimed it for update operations
        current_records_by_deployment_name.delete(deployment_name)
      else
        to_create << deployment
      end
    end

    # Any records remaining in the hash were not in the incoming deployments, so they should be deleted
    to_delete = current_records_by_deployment_name.values

    GitHub.logger.debug("Cluster deployment record changes categorized for cluster #{@cluster}: to_create=#{to_create.size}, to_update=#{to_update.size}, to_delete=#{to_delete.size}", "gh.cluster" => @cluster)
    { to_create: to_create, to_delete: to_delete, to_update: to_update }
  end

  sig { params(deployments: T.nilable(T::Array[T::Hash[Symbol, T.untyped]])).void }
  def build_deployment_templates!(deployments)
    return if deployments.nil?

    templates_by_digest = {}
    # Check that if multiple deployments have the same digest,
    # they also have the same name and version.
    found_deployment_names = {}
    found_digests = {}
    symbolized_deployments = deployments.map(&:symbolize_keys)
    symbolized_deployments.each do |deployment|
      # validate the provided artifact parameters are identical across all deployment entries
      digest = deployment[:digest]
      name = deployment[:name]
      version = deployment[:version]
      deployment_name = deployment[:deployment_name]

      if found_digests.key?(digest)
        found_name, found_version = found_digests[digest]
        if found_name != name || found_version != version
          raise ErrConflictingDeploymentInfo.new(digest, name, version, found_name, found_version)
        end
      else
        found_digests[digest] = [name, version]
      end

      raise ErrDuplicateDeploymentName.new if found_deployment_names.key?(deployment_name)
      found_deployment_names[deployment_name] = true

      deployment_data = deployment.slice(:github_repository, :cluster, :deployment_name, :logical_environment, :physical_environment, :runtime_risks, :tags, :status)
      deployment_data = deployment_data.merge({
        cluster: cluster,
        logical_environment: logical_environment,
        physical_environment: physical_environment
      })
      artifact_data = deployment.slice(:digest, :name, :version)
      artifact_template = ArtifactTemplate.new(artifact_data)

      deployment_template = DeploymentTemplate.new(org.id, artifact_template, deployment_data)
      (templates_by_digest[digest] ||= []) << deployment_template
    end

    self.deployment_templates = templates_by_digest
  end

  # Validate that the user has not submitted runtime-risk or runtime-risks
  # as tag names with the 'tags' request parameter
  sig { params(tags: T.nilable(T::Hash[Symbol, T.untyped])).void }
  def self.validate_deployment_record_tags!(tags)
    return if tags.nil?

    tags.each do |key, _|
      key_normalized = key.to_s.downcase.tr("-", "_")
      raise ErrInvalidTag.new(key) if key_normalized.start_with?("runtime_risk")
    end
  end

  sig { returns(Organization) }
  attr_reader :org

  sig { returns(String) }
  attr_reader :cluster

  sig { returns(String) }
  attr_reader :logical_environment

  sig { returns(String) }
  attr_reader :physical_environment

  sig { returns(T::Hash[String, T::Array[DeploymentTemplate]]) }
  attr_accessor :deployment_templates

  def initialize(org, cluster, logical_environment, physical_environment)
    @org = org
    @cluster = cluster
    @logical_environment = logical_environment
    @physical_environment = physical_environment
  end

  # Associates artifacts with deployment records and returns repository IDs for permission validation.
  # Attempts to fetch attestation identifiers from the TMA for each artifact digest.
  # If TMA lookup fails or returns no attestations, falls back to using explicitly provided github_repository names.
  # Returns unique Repository IDs that are used for permission checks.
  sig { returns(T::Array[Integer]) }
  def set_artifact_linkage_and_return_repository_ids
    digests = deployment_templates.keys

    # first attempt to fetch attestation and repository IDs from TMA
    attestation_identifiers_by_digest_from_tma = T.let({}, T::Hash[String, T::Array[{ attestation_id: Integer, repository_id: Integer }]])
    begin
      attestation_identifiers_by_digest_from_tma = ArtifactMetadataManager::fetch_attestation_identifiers_from_tma!(org, digests)
    rescue ArtifactMetadataManager::ErrTrustMetadata => e
      GitHub.logger.error("call to fetch attestations from TMA with org #{org.id} and digests #{digests.join(', ')} failed", "gh.org.id" => org.id, "gh.repo.attestation.subject_digests" => digests)
      # If there was an error fetching from TMA, the only way to recover is if a github repo name
      # was provided for every digest. If not, raise the error.
      deployment_templates.each_value do |deployments|
        deployments.each do |deployment|
          if deployment.linkage.github_repository.nil?
            raise ArtifactMetadataManager::ErrTrustMetadata
          end
        end
      end
    end

    # gather all repository IDs to return so they can be used for permissions checks
    repo_ids = []

    # Batch-load repositories by name for deployments not found in TMA
    fallback_repo_names = deployment_templates.each_with_object([]) do |(digest, deployments), names|
      next if attestation_identifiers_by_digest_from_tma.key?(digest)
      deployments.each do |deployment|
        names << deployment.linkage.github_repository if deployment.linkage.github_repository.present?
      end
    end
    repos_by_name = Repository.where(name: fallback_repo_names.uniq, owner_id: org.id).index_by(&:name)

    # Combine results from TMA with any provided digests that did not have attestations
    deployment_templates.each do |digest, deployments|
      deployments.each do |deployment|
        if attestation_identifiers_by_digest_from_tma.key?(digest)
          identifiers = T.must(attestation_identifiers_by_digest_from_tma[digest])
          deployment.linkage.repo_and_attestation_ids = identifiers.map { |id| id.merge(artifact_metadata_id: nil) }
          repo_ids.concat(identifiers.map { |ids| ids[:repository_id] })
        else
          # If no attestations were found from TMA, we can only proceed if a github repo name was provided
          next if deployment.linkage.github_repository.nil?

          found = repos_by_name[deployment.linkage.github_repository]
          if found.nil?
            raise ArtifactMetadataManager::ErrNoRepoAccess.new(org.id)
          end

          # No attestations found, but github repo name was provided, so return repository ID with nil attestation ID
          deployment.linkage.repo_and_attestation_ids = [{
            artifact_metadata_id: nil,
            attestation_id: nil,
            repository_id: found.id
          }]
          repo_ids << found.id
        end
      end
    end
    repo_ids.uniq
  end
end
