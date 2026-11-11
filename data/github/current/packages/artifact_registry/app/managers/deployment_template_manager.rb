# typed: true
# frozen_string_literal: true

class DeploymentTemplateManager
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

  class ErrRepositoryNotFound < StandardError
    attr_reader :repositories

    sig { params(repositories: T::Array[String]).void }
    def initialize(repositories)
      @repositories = repositories
      super("Repositories not found: #{repositories.join(', ')}")
    end

    def response_message
      {
        "cause" => "One or more repositories do not exist",
        "repositories" => @repositories
      }
    end
  end

  sig { params(deployments: T.nilable(T::Array[T::Hash[Symbol, T.untyped]]), metrics: SetClusterRecordMetrics).void }
  def build_deployment_templates!(deployments, metrics)
    return if deployments.nil?

    # Deduplicate identical incoming entries with a set
    seen = Set.new
    templates_by_digest = {}
    found_deployment_names = Set.new
    found_digests = {}
    duplicate_digests_found = T.let(false, T::Boolean)

    # Single pass: deduplicate + validate + build templates
    deployments.each do |deployment_raw|
      deployment = deployment_raw.symbolize_keys

      # Skip if already seen, add returns nil if duplicate
      next unless seen.add?(deployment)

      digest = deployment[:digest]
      name = deployment[:name]
      version = deployment[:version]
      deployment_name = deployment[:deployment_name]

      # Keep track of whether there are deployment entries that include
      # identical artifact digests but different names or versions
      # We publish a metric after processing all entries to track how often this happens
      if found_digests[digest]
        found_name, found_version = found_digests[digest]
        if found_name != name || found_version != version
          duplicate_digests_found = true
        end
      else
        found_digests[digest] = [name, version]
      end

      # Validate unique deployment names
      raise ErrDuplicateDeploymentName.new if found_deployment_names.include?(deployment_name)
      found_deployment_names.add(deployment_name)

      # Check if the template has the github_repository parameter set
      # If all entries have the parameter set, we can defer TMA call to a background job
      # instead of calling it synchronously
      if deployment[:github_repository].blank?
        self.can_defer_tma_call = false
      else
        github_repo_names << deployment[:github_repository]
      end
      all_digests << digest

      # Build templates
      artifact_data = deployment.slice(:digest, :name, :version)
      deployment_data = deployment.slice(:github_repository, :cluster, :deployment_name, :logical_environment, :physical_environment, :runtime_risks, :tags, :status)
      deployment_data.merge!(
        cluster: cluster,
        logical_environment: logical_environment,
        physical_environment: physical_environment
      )
      artifact_template = ArtifactTemplate.new(artifact_data)
      deployment_template = DeploymentTemplate.new(org.id, artifact_template, deployment_data)

      (templates_by_digest[digest] ||= []) << deployment_template
    end

    # Publish a metric to track how often users are submitting multiple deployment entries with the same artifact
    # digest but different names or versions. This will be used to determine how often this use case is encountered
    # and inform how we prioritize iterating on this experience
    if duplicate_digests_found
      metrics.publish_distribution_metric("conflicting_deployment_artifact_info", 1)
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

  sig { returns T::Boolean }
  attr_accessor :can_defer_tma_call

  sig { returns T::Set[String] }
  attr_accessor :github_repo_names

  sig { returns T::Set[String] }
  attr_accessor :all_digests

  sig { returns T::Array[DeploymentTemplate] }
  attr_accessor :unresolvable_templates

  def initialize(org, cluster, logical_environment, physical_environment)
    @org = org
    @cluster = cluster
    @logical_environment = logical_environment
    @physical_environment = physical_environment
    @can_defer_tma_call = true
    @github_repo_names = T.let(Set.new, T::Set[String])
    @all_digests = T.let(Set.new, T::Set[String])
    @unresolvable_templates = T.let([], T::Array[DeploymentTemplate])
  end

  # Associates artifacts with deployment records and returns repository IDs for permission validation.
  # Attempts to fetch attestation identifiers from the TMA for each artifact digest.
  # If TMA lookup fails or returns no attestations, falls back to using explicitly provided github_repository names.
  # Returns unique Repository IDs that are used for permission checks.
  sig { params(metrics: SetClusterRecordMetrics).returns(T::Array[Integer]) }
  def set_artifact_linkage_and_return_repository_ids(metrics)
    # If all templates have a github repository parameter, we can validate that they
    # resolve to repositories up front. We still need to continue into the linkage
    # population path so downstream validation and persistence see populated
    # repo_and_attestation_ids.
    if can_defer_tma_call
      repo_names = github_repo_names.to_a
      GitHub.logger.info("Fetching repository IDs with github repository names #{repo_names}", "gh.org.id" => org.id)

      repos_by_name = Repository.where(owner_id: org.id, name: repo_names).pluck(:name, :id).to_h
      missing_repo_names = repo_names - repos_by_name.keys
      if missing_repo_names.present?
        GitHub.logger.info("Repositories not found when deferring tma call", "gh.org.id" => org.id)
        raise ErrRepositoryNotFound.new(missing_repo_names)
      end

      deployment_templates.each do |_digest, deployments|
        deployments.each do |deployment|
          repo_name = deployment.linkage.github_repository
          repo_id = T.must(repos_by_name[repo_name])
          linkage = T.let([{ repository_id: repo_id, attestation_id: nil, artifact_metadata_id: nil }], T::Array[{ artifact_metadata_id: T.nilable(Integer), attestation_id: T.nilable(Integer), repository_id: Integer }])
          deployment.linkage.repo_and_attestation_ids = linkage
        end
      end

      return repos_by_name.values
    end

    GitHub.logger.info("Fetching repository and attestation IDs with TMA", "gh.org.id" => org.id)
    set_artifact_linkage_with_tma(metrics)
  end

  sig { params(metrics: SetClusterRecordMetrics).returns(T::Array[Integer]) }
  def set_artifact_linkage_with_tma(metrics)
    digests = all_digests.to_a
    # first attempt to fetch attestation and repository IDs from TMA
    attestation_identifiers = T.let({}, T::Hash[String, T::Array[{ attestation_id: Integer, repository_id: Integer }]])
    begin
      attestation_identifiers = ArtifactMetadataManager::fetch_validated_attestation_identifiers!(org, digests, metrics)
    rescue ArtifactMetadataManager::ErrTrustMetadata => e
      GitHub.logger.error("call to fetch attestations from TMA with org #{org.id} and digests #{digests.join(', ')} failed", "gh.org.id" => org.id, "gh.repo.attestation.subject_digests" => digests)
      raise ArtifactMetadataManager::ErrTrustMetadata
    end

    # gather all repository IDs to return so they can be used for permissions checks
    repo_ids = []

    # Separate deployments into TMA-found and fallback paths
    fallback_deployments = []
    fallback_repo_names = []

    deployment_templates.each do |digest, deployments|
      if attestation_identifiers.key?(digest)
        # TMA found: set linkage directly
        identifiers = T.must(attestation_identifiers[digest])
        deployments.each do |deployment|
          deployment.linkage.repo_and_attestation_ids = identifiers.map { |id| id.merge(artifact_metadata_id: nil) }
        end
        repo_ids.concat(identifiers.map { |ids| ids[:repository_id] })
      else
        # TMA not found: collect for fallback
        deployments.each do |deployment|
          if deployment.linkage.github_repository.present?
            fallback_deployments << deployment
            fallback_repo_names << deployment.linkage.github_repository
          else
            @unresolvable_templates << deployment
          end
        end
      end
    end

    fallback_repo_ids = Repository.where(owner_id: org.id, name: fallback_repo_names.uniq)
      .index_by(&:name)
      .transform_values(&:id)

    repos_not_found = fallback_repo_names.uniq - fallback_repo_ids.keys
    raise ErrRepositoryNotFound.new(repos_not_found) if repos_not_found.any?

    fallback_deployments.each do |deployment|
      repo_name = deployment.linkage.github_repository
      repo_id = fallback_repo_ids[repo_name]
      deployment.linkage.repo_and_attestation_ids = [{ repository_id: repo_id, attestation_id: nil }]
      repo_ids << repo_id
    end
    repo_ids.uniq
  end
end
