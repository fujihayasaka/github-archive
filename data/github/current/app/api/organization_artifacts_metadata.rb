# typed: true
# frozen_string_literal: true

class Api::OrganizationArtifactsMetadata < Api::App
  ERR_NO_ARTIFACTS_FOUND = "no artifacts found"
  STATUS_DECOMMISSIONED = "decommissioned"
  # max number of pages to fetch from TMA when looking for attestations
  # to avoid infinite loops
  MAX_PAGES = 50

  post "/organizations/:organization_id/artifacts/metadata/storage-record", operation_id: "orgs/create-artifact-storage-record", read_from_replicas: true do
    GitHub.tracer.in_span("Api::OrganizationArtifactsMetadata#create_storage_record", kind: :internal) do |span|
      reject_on_ghes!
      org = find_org!

      # We only check for authenticated users against the org here, and then once
      # we find the repositories, we check if the user has write access to each
      # repository.
      control_access :authenticated_user,
      resource: org,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

      data = receive_with_openapi

      Rails.logger.info("Create artifact storage records with #{data} for organization #{org.id}")
      symbolized_data = data.symbolize_keys
      span.add_event("creating storage records by org and subject digest", attributes: { "gh.repo.attestation.subject_digest" => symbolized_data[:digest], "gh.org.id" => org.id })

      records = create_storage_records!(org, data)

      status = records.first.artifact_metadata&.status
      send_hydro_messages_for_storage_records(status, records)

      new_data = { total_count: records.length, records: records }
      deliver :artifact_storage_records_hash, new_data
    end
  end

  post "/organizations/:organization_id/artifacts/storage-record/artifactory", operation_id: "orgs/create-artifactory-storage-record", read_from_replicas: true do
    GitHub.tracer.in_span("Api::OrganizationArtifactsMetadata#create_artifactory_storage_record", kind: :internal) do |span|
      require_authentication!
      org = find_org!

      # We only check for authenticated users against the org here, and then once
      # we find the repositories, we check if the user has write access to each
      # repository.
      control_access :authenticated_user,
        resource: org,
        challenge: true,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      data = receive_with_openapi

      Rails.logger.info("Store artifact storage record #{data} for organization #{org.id} from Artifactory")
      symbolized_data = data.symbolize_keys
      digest = symbolized_data[:sha256]
      span.add_event("creating artifactory storage record by org and subject digest", attributes: { "gh.repo.attestation.subject_digest" => "sha256:#{digest}", "gh.org.id" => org.id })

      # parse artifactory specific body format to one the helper function recognizes
      artifact_url = data["artifact_url"]
      match = artifact_url.match(%r{\Ahttps://[^/]+/[^/]+})
      unless match
        err_msg = "Invalid artifact_url format, must contain at least two path segments: #{artifact_url}"
        Rails.logger.error(err_msg)
        deliver_error!(422, message: err_msg)
      end
      registry_url = match[0]

      parsed_data = {
        "artifact_path" => data["path"],
        "artifact_url" => artifact_url,
        "digest" => "sha256:#{data["sha256"]}",
        "name" => data["artifact_name"],
        "registry_url" => registry_url,
        "repository" => data["repo_key"],
        "source_registry" => ArtifactStorageRecord::SOURCE_REGISTRY_ARTIFACTORY,
        "status" => "active",
      }

      records = create_storage_records!(org, parsed_data, include_source_registry: true)
      send_hydro_messages_for_storage_records(parsed_data["status"], records)

      resp_body = { total_count: records.length, records: records }
      deliver :artifact_storage_records_hash, resp_body
    end
  end

  get "/organizations/:organization_id/artifacts/:subject_digest/metadata/storage-records", operation_id: "orgs/list-artifact-storage-records" do
    GitHub.tracer.in_span("Api::OrganizationArtifactsMetadata#get_storage_records", kind: :internal) do |span|
      reject_on_ghes!
      org = find_org!

      subject_digest = params[:subject_digest]

      Rails.logger.info("Get artifact storage record for subject #{subject_digest} in organization #{org.id}")
      span.add_event("fetching storage records by org and subject digest", attributes: { "gh.repo.attestation.subject_digest" => subject_digest, "gh.org.id" => org.id })

      control_access :authenticated_user,
        resource: org,
        challenge: true,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      records = ArtifactMetadata
        .where(owner_id: org.id, digest: subject_digest)
        .includes(:repository, :storage_records)
        .select { |record| access_allowed?(:read_artifact_metadata, resource: record.repository, allow_integrations: true, allow_user_via_granular_actor: true) }
        .flat_map(&:storage_records)

      deliver_error!(404, message: ERR_NO_ARTIFACTS_FOUND) unless records.any?

      deliver :artifact_storage_records_hash, { records: records, total_count: records.count }
    end
  end

  post "/organizations/:organization_id/artifacts/metadata/deployment-record", operation_id: "orgs/create-artifact-deployment-record", read_from_replicas: true do
    GitHub.tracer.in_span("Api::OrganizationArtifactsMetadata#create_deployment_records", kind: :internal) do |span|
      reject_on_ghes!
      org = find_org!

      # We only check for authenticated users against the org here, and then once
      # we find the repositories, we check if the user has write access to each
      # repository.
      control_access :authenticated_user,
        resource: org,
        challenge: true,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      data = receive_with_openapi

      Rails.logger.info("Store artifact deployment record #{data} for organization #{org.id}")
      symbolized_data = data.symbolize_keys
      validate_deployment_record_tags!(symbolized_data)
      span.add_event("creating deployment record by org and subject digest", attributes: { "gh.repo.attestation.subject_digest" => symbolized_data[:digest], "gh.org.id" => org.id })

      records = create_or_update_deployment_records!(org, data)
      deliver :artifact_deployment_records_hash, { records: records, total_count: records.count }
    end
  end

  get "/organizations/:organization_id/artifacts/:subject_digest/metadata/deployment-records", operation_id: "orgs/list-artifact-deployment-records" do
    GitHub.tracer.in_span("Api::OrganizationArtifactsMetadata#get_deployment_records", kind: :internal) do |span|
      reject_on_ghes!
      org = find_org!

      # We only check for authenticated users against the org here, and then once
      # we find the repositories, we check if the user has read access to each
      # repository.
      control_access :authenticated_user,
        resource: org,
        challenge: true,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      subject_digest = params[:subject_digest]

      Rails.logger.info("Get artifact deployment records for subject #{subject_digest} in organization #{org.id}")
      span.add_event("fetching deployment records by org and subject digest", attributes: { "gh.repo.attestation.subject_digest" => subject_digest, "gh.org.id" => org.id })

      records = ArtifactMetadata
        .where(owner_id: org.id, digest: subject_digest)
        .includes(:repository, :deployment_records)
        .select { |record| access_allowed?(:read_artifact_metadata, resource: record.repository, allow_integrations: true, allow_user_via_granular_actor: true) }
        .flat_map(&:deployment_records)

      deliver_error!(404, message: ERR_NO_ARTIFACTS_FOUND) unless records.any?

      deliver :artifact_deployment_records_hash, { records: records, total_count: records.count }
    end
  end

  post "/organizations/:organization_id/artifacts/metadata/deployment-record/cluster/:cluster", operation_id: "orgs/set-cluster-deployment-records", read_from_replicas: true do
    GitHub.tracer.in_span("Api::OrganizationArtifactsMetadata#set_cluster_deployment_records", kind: :internal) do |span|
      reject_on_ghes!
      org = find_org!

      # We only check for authenticated users against the org here, and then once
      # we find the repositories, we check if the user has write access to each
      # repository.
      control_access :authenticated_user,
        resource: org,
        challenge: true,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      data = receive_with_openapi

      Rails.logger.info("Set cluster deployment records for organization #{org.id} with #{data}")
      span.add_event("set deployment records by org and cluster", attributes: { "gh.org.id" => org.id })

      symbolized_data = data.symbolize_keys
      validate_set_cluster_record_params!(symbolized_data)
      new_records = set_cluster_scoped_deployment_records!(org, symbolized_data)

      deliver :artifact_deployment_records_hash, { records: new_records, total_count: new_records.count }
    end
  end

  private

  # The larger Artifact Registry feature set is not supported on GHES
  def reject_on_ghes!
    if GitHub.single_tenant_enterprise?
      deliver_error! 404
    end
  end

  sig { params(data: T::Hash[Symbol, T.untyped]).void }
  def validate_set_cluster_record_params!(data)
    deployments = data[:deployments]
    return if deployments.nil?

    # Check that if multiple deployments have the same digest,
    # they also have the same name and version.
    found_digests = {}
    symbolized_deployments = deployments.map(&:symbolize_keys)
    symbolized_deployments.each do |deployment|
      # validate the provided artifact parameters are identical across all deployment entries
      digest = deployment[:digest]
      name = deployment[:name]
      version = deployment[:version]

      if found_digests.key?(digest)
        found_name, found_version = found_digests[digest]
        if found_name != name || found_version != version
          deliver_error!(400, message: "Conflicting deployment info for digest #{digest}: (#{found_name}, #{found_version}) vs (#{name}, #{version})")
        end
        next
      end

      found_digests[digest] = [name, version]

      # validate that the deployment tags do not contain runtime-risk or runtime-risks
      validate_deployment_record_tags!(deployment)
    end
  end

  # Validate that the user has not submitted runtime-risk or runtime-risks
  # as tag names with the 'tags' request parameter
  sig { params(data: T::Hash[Symbol, T.untyped]).void }
  def validate_deployment_record_tags!(data)
    tags = data[:tags]
    return if tags.nil?

    tags.each do |key, _|
      key_normalized = key.to_s.downcase.tr("-", "_")
      if key_normalized.start_with?("runtime_risk")
        deliver_error!(400, message: "Invalid tag: #{key}. Custom tags cannot begin with runtime risk")
      end
    end
  end

  sig { params(status: String, records: T::Array[ArtifactStorageRecord]).void }
  def send_hydro_messages_for_storage_records(status, records)
    hydro_event = case status.downcase
    when ArtifactMetadata.statuses[:active].to_s.downcase
      "artifacts_metadata.artifact_storage_record.create"
    when ArtifactMetadata.statuses[:eol].to_s.downcase
      "artifacts_metadata.artifact_storage_record.update"
    when ArtifactMetadata.statuses[:deleted].to_s.downcase
      "artifacts_metadata.artifact_storage_record.delete"
    else
      raise ArgumentError, "Unknown status: #{status}"
    end

    records.each do |record|
      GlobalInstrumenter.instrument(hydro_event, {
        storage_record_id: record.id,
        attestation_id: record.artifact_metadata&.attestation_id,
        org_id: record.artifact_metadata&.owner_id,
        repo_id: record.artifact_metadata&.repository_id,
        subject_digest: record.artifact_metadata&.digest,
      })
    end
  end

  sig { params(org: Organization, digest: String).returns(T.untyped) }
  def find_provenance_attestations_from_digest_and_org!(org, digest)
    # Because the TMA returns thirty attestations at most, we need to handle cases where more than thirty attestations are found
    attestation_identifiers = []
    end_cursor = T.let(nil, T.untyped)
    pages = 0
    # Loop until the has_next_page field in the response is false.
    # Use the response's end_cursor field to fetch the next batch of attestations.
    loop do
      pages += 1
      if pages > MAX_PAGES
        # if we reach the maximum number of pages, log a warning, break the loop, and return what we have
        Rails.logger.warn("TMA pagination exceeded maximum of #{MAX_PAGES} pages for organization #{org.id} with digest #{digest}")
        break
      end

      response = TrustMetadata.get_attestation_identifiers_by_subject_digest(org, [digest], predicate_type: "provenance", after: end_cursor)
      if !response.call_succeeded?
        if response.status == 404
          return []
        end

        Rails.logger.error("call to TMA with org #{org.id} and digest #{digest} failed")
        deliver_error! 500
      end

      # The TMA should return a 404 if no attestations are found but just in case,
      # check that the response has a value and that there are attestations
      resp_body = response.value
      if resp_body.nil? || resp_body.attestation_identifiers.empty?
        return []
      end

      attestation_identifiers.concat(resp_body.attestation_identifiers)

      # stop when there is no next page
      break unless resp_body&.page_info&.hasNextPage
      end_cursor = resp_body.page_info.endCursor
    end

    # Filter the attestations to only include those where the user has write access to the repository.
    filtered = attestation_identifiers.filter do |entry|
      repo = Repository.find_by(id: entry.repository_id, owner_id: org.id)
      access_allowed?(:write_artifact_metadata, resource: repo, allow_integrations: true, allow_user_via_granular_actor: true)
    end

    filtered
  end

  # Fetch repository IDs and attestation IDs based on whether provenance attestations
  # associated with the given org and digest exist or if the github-repository
  # request body parameter is provided
  sig { params(org: Organization, digest: String, github_repo_name: T.nilable(String)).returns(T::Array[T::Hash[Symbol, Integer]]) }
  def get_repository_and_attestation_ids!(org, digest, github_repo_name)
    # Default to checking for provenance attestations using the digest first
    # If any are found, return the associated repository IDs and attestation IDs
    deliver_error!(422, message: "digest is required") if digest.blank?
    attestation_identifiers = find_provenance_attestations_from_digest_and_org!(org, digest)
    if attestation_identifiers.any?
      return attestation_identifiers.map { |entry| { repository_id: entry.repository_id, attestation_id: entry.attestation_id } }
    end

    # If no attestations are found, use the provided github repo name to fetch the repository ID
    if github_repo_name.nil?
      deliver_error!(404, message: ERR_NO_ARTIFACTS_FOUND)
    end

    # For now we only expect the repo name without owner, since owner is provided in the
    # endpoint path. This may change in the future while the API is still in beta.
    found = Repository.find_by(name: github_repo_name, owner_id: org.id)
    if found.nil?
      deliver_error!(404, message: ERR_NO_ARTIFACTS_FOUND)
    end

    if !access_allowed?(:write_artifact_metadata, resource: found, allow_integrations: true, allow_user_via_granular_actor: true)
      return []
    end

    [{ repository_id: found.id, attestation_id: nil }]
  end

  def get_storage_record_status(data)
    parsed_data = data.symbolize_keys
    status = ArtifactMetadata.statuses[parsed_data[:status].to_s.downcase]
    if status.nil?
      status = ArtifactMetadata.statuses[:active]
    end
    status
  end

  sig { params(org: Organization, data: T::Hash[T.any(Symbol, String), String], include_source_registry: T::Boolean).returns(T.untyped) }
  def create_storage_records!(org, data, include_source_registry: false)
    parsed_data = data.symbolize_keys
    digest = parsed_data[:digest]
    github_repo_name = parsed_data[:github_repository]
    repo_and_attestation_ids = get_repository_and_attestation_ids!(org, digest, github_repo_name)

    storage_records = []
    begin
      # because the function expects:
      # 1. creating multiple artifact storage records
      # 2. the creation or update of existing artifact metadata records
      # it needs to account for potential failures when writing to the database for both cases.
      # Preload all existing ArtifactMetadata records for this org/digest/repository_id set
      repository_ids = repo_and_attestation_ids.map { |e| e[:repository_id] }
      existing_artifacts = ArtifactMetadata.where(
        owner_id: org.id,
        digest: digest,
        repository_id: repository_ids
      ).index_by(&:repository_id)

      with_write(clusters: [ApplicationRecord::ArtifactRegistry]) do
        repo_and_attestation_ids.each do |entry|
          ArtifactMetadata.transaction do
            repository_id, attestation_id = entry.values_at(:repository_id, :attestation_id)
            artifact = existing_artifacts[repository_id]
            artifact ||= create_artifact_metadata_record(org, parsed_data, T.must(repository_id), attestation_id)

            status = get_storage_record_status(parsed_data)
            artifact.update!(status: status)

            # Because we currently only want to store the source registry if it's explicitly
            # for a supported integration like JFrog Artifactory, we check that the include_source_registry parameter is set to true.
            # If not set to true, the source_registry field is not included.
            # The parameter defaults to false and must be explicitly set to true to write to the source_registry field.
            attrs = {
              artifact_path: parsed_data[:artifact_path],
              artifact_url: parsed_data[:artifact_url],
              registry_repository_name: parsed_data[:repository],
              registry_url: parsed_data[:registry_url],
              source_registry: (parsed_data[:source_registry] if include_source_registry)
            }.compact

            ArtifactStorageRecord.transaction do
              # Because there may be multiple artifact metadata records with identical org IDs and digests but different
              # repository IDs, check whether there is already a storage record associated with each artifact. This will prevent
              # the code from creating duplicate storage records for the same artifact metadata record instead of updating existing records.
              storage_record = ArtifactStorageRecord.find_or_initialize_by(artifact_metadata: artifact)
              # If storage_record already exists, this updates the attributes. If the record was
              # just initialized, this assigns the attributes for the first time.
              storage_record.assign_attributes(attrs)
              storage_record.save!

              storage_records << storage_record
            end
          end
        end
      end
    rescue => e
      Rails.logger.error("Error creating storage records for organization #{org.id}: #{e.message}")
      deliver_error! 500
    end

    storage_records
  end

  sig { params(org: Organization, data: T::Hash[T.any(Symbol, String), String]).returns(T.untyped) }
  def create_or_update_deployment_records!(org, data)
    parsed_data = data.symbolize_keys
    digest = parsed_data[:digest]
    github_repo_name = parsed_data[:github_repository]
    repo_and_attestation_ids = get_repository_and_attestation_ids!(org, digest, github_repo_name)

    deployment_records = []
    begin
      # because the function expects:
      # 1. creating multiple artifact storage records
      # 2. the creation or update of existing artifact metadata records
      # it needs to account for potential failures when writing to the database for both cases.
      # Preload all existing ArtifactMetadata records for this org/digest/repository_id set
      repository_ids = repo_and_attestation_ids.map { |e| e[:repository_id] }
      existing_artifacts = ArtifactMetadata.where(
        owner_id: org.id,
        digest: digest,
        repository_id: repository_ids
      ).index_by(&:repository_id)

      with_write(clusters: [ApplicationRecord::ArtifactRegistry]) do
        repo_and_attestation_ids.each do |entry|
          repository_id, attestation_id = entry.values_at(:repository_id, :attestation_id)
          ArtifactMetadata.transaction do
            artifact = existing_artifacts[repository_id]
            artifact ||= create_artifact_metadata_record(org, parsed_data, T.must(repository_id), attestation_id)

            deployment_params = {
              logical_environment: parsed_data[:logical_environment],
              physical_environment: parsed_data[:physical_environment] || "",
              cluster: parsed_data[:cluster] || "",
              deployment_name: parsed_data[:deployment_name]
            }

            # repository_id must not be null
            repository_id = T.must(repository_id)
            deployment_record = ArtifactDeploymentRecord.record_by_deploy_params_and_repo(deployment_params, repository_id)
            nil_record = deployment_record.nil?

            if nil_record
              deployment_params[:artifact_metadata_id] = artifact.id
              deployment_params[:owner_id] = org.id
              deployment_record = ArtifactDeploymentRecord.create(deployment_params)
              send_hydro_message_for_deployment_record("artifacts_metadata.artifact_deployment_record.create", deployment_record)
            elsif deployment_record.artifact_metadata != artifact
              old_artifact = deployment_record.artifact_metadata
              deployment_record.update(artifact_metadata: artifact)
              old_artifact.soft_delete if old_artifact&.standalone?
            end

            deployment_record.update_all_tags(parsed_data[:tags], parsed_data[:runtime_risks])
            # There's not a singular place for updates, so check that we didn't just create the record
            unless nil_record
              send_hydro_message_for_deployment_record("artifacts_metadata.artifact_deployment_record.update", deployment_record)
            end

            if parsed_data[:status] == STATUS_DECOMMISSIONED
              deployment_record.decommission
              artifact.soft_delete if artifact.standalone?
              send_hydro_message_for_deployment_record("artifacts_metadata.artifact_deployment_record.delete", deployment_record)
            end

            deliver_error!(422) if deployment_record.errors.any?
            deployment_records << deployment_record
          end
        end
      end
    rescue => e
      Rails.logger.error("Error creating deployment records for organization #{org.id}: #{e.message}")
      deliver_error! 500
    end

    deployment_records
  end

  sig { params(org: Organization, data: T::Hash[T.any(Symbol, String), String]).returns(T.untyped) }
  def create_deployment_records!(org, data)
    parsed_data = data.symbolize_keys
    digest = parsed_data[:digest]
    github_repo_name = parsed_data[:github_repository]
    repo_and_attestation_ids = get_repository_and_attestation_ids!(org, digest, github_repo_name)
    if repo_and_attestation_ids.empty?
      deliver_error!(404, message: ERR_NO_ARTIFACTS_FOUND)
    end

    deployment_records = []
    begin
      # because the function expects:
      # 1. creating multiple artifact deployment records
      # 2. creating or updating existing artifact metadata records
      # it needs to account for potential failures when writing to the database for both cases.
      # Preload all existing ArtifactMetadata records for this cluster, logical env, physical env, and digest set
      repository_ids = repo_and_attestation_ids.map { |e| e[:repository_id] }
      existing_artifacts = ArtifactMetadata.where(
        owner_id: org.id,
        digest: digest,
        repository_id: repository_ids
      ).index_by(&:repository_id)

      with_write(clusters: [ApplicationRecord::ArtifactRegistry]) do
        repo_and_attestation_ids.each do |entry|
          repository_id, attestation_id = entry.values_at(:repository_id, :attestation_id)
          ArtifactMetadata.transaction do
            artifact = existing_artifacts[repository_id]
            artifact ||= create_artifact_metadata_record(org, parsed_data, T.must(repository_id), attestation_id)

            deployment_params = {
              logical_environment: parsed_data[:logical_environment],
              physical_environment: parsed_data[:physical_environment] || "",
              cluster: parsed_data[:cluster] || "",
              deployment_name: parsed_data[:deployment_name],
            }

            # repository_id must not be null
            repository_id = T.must(repository_id)
            deployment_record = ArtifactDeploymentRecord.deployed_record_by_deploy_params_and_repo(deployment_params, repository_id)
            nil_record = deployment_record.nil?

            if nil_record
              deployment_params[:artifact_metadata_id] = artifact.id
              deployment_params[:owner_id] = org.id
              deployment_record = ArtifactDeploymentRecord.create(deployment_params)
              send_hydro_message_for_deployment_record("artifacts_metadata.artifact_deployment_record.create", deployment_record)
              deployment_record.update_all_tags(parsed_data[:tags], parsed_data[:runtime_risks])
            end

            deliver_error!(422) if deployment_record.errors.any?
            deployment_records << deployment_record
          end
        end
      end
    rescue => e
      Rails.logger.error("Error creating deployment records for organization #{org.id}: #{e.message}")
      deliver_error! 500
    end

    deployment_records
  end

  sig { params(org: Organization, data: T::Hash[T.any(Symbol, String), T.untyped]).returns(T.untyped) }
  def set_cluster_scoped_deployment_records!(org, data)
    data = data.symbolize_keys
    cluster = params[:cluster]
    logical_env = data[:logical_environment] || ""
    physical_env = data[:physical_environment] || ""

    # fetch current records by cluster, logical env, physical env
    current_cluster_records = ArtifactDeploymentRecord.records_with_cluster(logical_env, physical_env, cluster, org.id)
    if current_cluster_records.any?
      # Check that actor has the needed permission against all associated repositories. If the actor does not have
      # the necessary permissions, return a 403 error and do not decommission or create new ones.
      current_cluster_records.each do |record|
        repo = Repository.find_by(id: record.artifact_metadata.repository_id, owner_id: org.id)
        if !access_allowed?(:write_artifact_metadata, resource: repo, allow_integrations: true, allow_user_via_granular_actor: true)
          deliver_error!(403, message: "insufficient access to decommission existing deployment records")
        end
      end

      # check that the actor has the needed permission against all repositories for new records to be created
      # we only want to attempt updating the cluster set if the actor has the necessary permissions for all
      # repositories associated with existing and new records
      new_records_data = data[:deployments] || []
      new_records_data.each do |record|
        parsed_data = record.symbolize_keys
        digest = parsed_data[:digest]
        github_repo_name = parsed_data[:github_repository]

        repo_and_attestation_ids = get_repository_and_attestation_ids!(org, digest, github_repo_name)
        if repo_and_attestation_ids.empty?
          deliver_error!(403, message: "insufficient access to create new deployment records")
        end
      end

      # only decommission records the actor has appropriate access to
      to_decommission = current_cluster_records.map(&:id)
      with_write(clusters: [ApplicationRecord::ArtifactRegistry]) do
        ArtifactDeploymentRecord.where(id: to_decommission).update_all(deleted_at: Time.now)
        # soft delete any standalone artifacts associated with the decommissioned records
        current_cluster_records.each do |r|
          artifact = r.artifact_metadata
          artifact.soft_delete if artifact&.standalone?
        end
      end
    end

    new_records_data = data[:deployments] || []
    # create records not in current set
    new_record_set = []
    new_records_data.each do |record|
      record_with_envs = record.merge({
        "logical_environment" => logical_env,
        "physical_environment" => physical_env,
        "cluster" => cluster
      })
      records = create_deployment_records!(org, record_with_envs)
      new_record_set.concat(records)
    end

    new_record_set
  end

  sig { params(org: Organization, data: T::Hash[T.any(Symbol, String), String], repository_id: Integer, attestation_id: T.nilable(Integer)).returns(T.untyped) }
  def create_artifact_metadata_record(org, data, repository_id, attestation_id)
    artifact = ArtifactMetadata.create!(
      owner_id: org.id,
      digest: data[:digest],
      repository_id: repository_id,
      attestation_id: attestation_id,
      name: data[:name],
      version: data[:version]
    )
    artifact
  end

  sig { params(event: String, record: ArtifactDeploymentRecord).void }
  def send_hydro_message_for_deployment_record(event, record)
    GlobalInstrumenter.instrument(event, {
      deployment_record_id: record.id,
      attestation_id: record.artifact_metadata&.attestation_id,
      org_id: record.artifact_metadata&.owner_id,
      repo_id: record.artifact_metadata&.repository_id,
      subject_digest: record.artifact_metadata&.digest,
    })
  end
end
