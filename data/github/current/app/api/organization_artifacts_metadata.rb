# typed: true
# frozen_string_literal: true

class Api::OrganizationArtifactsMetadata < Api::App
  ERR_NO_ARTIFACTS_FOUND = "no artifacts found"
  STATUS_DECOMMISSIONED = "decommissioned"

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

      GitHub.logger.info("Create artifact storage records with #{data} for organization #{org.id}",
        common_log_fields("gh.org.id" => org.id),
      )
      symbolized_data = data.symbolize_keys
      span.add_event("creating storage records by org and subject digest", attributes: { "gh.repo.attestation.subject_digest" => symbolized_data[:digest], "gh.org.id" => org.id })

      records = create_storage_records!(org, data)

      ArtifactRegistryHydroMessageManager.send_hydro_messages_for_storage_records(records)

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

      GitHub.logger.info("Store artifact storage record #{data} for organization #{org.id} from Artifactory", common_log_fields("gh.org.id" => org.id))
      symbolized_data = data.symbolize_keys
      digest = symbolized_data[:sha256]
      span.add_event("creating artifactory storage record by org and subject digest", attributes: { "gh.repo.attestation.subject_digest" => "sha256:#{digest}", "gh.org.id" => org.id })

      # parse artifactory specific body format to one the helper function recognizes
      artifact_url = data["artifact_url"]
      match = artifact_url.match(%r{\Ahttps://[^/]+/[^/]+})
      unless match
        err_msg = "Invalid artifact_url format, must contain at least two path segments: #{artifact_url}"
        GitHub.logger.error(err_msg, common_log_fields("gh.org.id" => org.id))
        deliver_error!(422, message: err_msg)
      end
      registry_url = match[0]

      parsed_data = {
        "artifact_path" => data["path"],
        "artifact_url" => artifact_url,
        "digest" => "sha256:#{data["sha256"]}",
        "github_repository" => data["github_repository"],
        "name" => data["artifact_name"],
        "registry_url" => registry_url,
        "repository" => data["repo_key"],
        "source_registry" => ArtifactStorageRecord::SOURCE_REGISTRY_ARTIFACTORY,
        "status" => "active",
        "version" => data["version"],
      }

      records = create_storage_records!(org, parsed_data, include_source_registry: true)
      ArtifactRegistryHydroMessageManager.send_hydro_messages_for_storage_records(records)

      resp_body = { total_count: records.length, records: records }
      deliver :artifact_storage_records_hash, resp_body
    end
  end

  get "/organizations/:organization_id/artifacts/:subject_digest/metadata/storage-records", operation_id: "orgs/list-artifact-storage-records" do
    GitHub.tracer.in_span("Api::OrganizationArtifactsMetadata#get_storage_records", kind: :internal) do |span|
      reject_on_ghes!
      org = find_org!

      subject_digest = params[:subject_digest]

      GitHub.logger.info("Get artifact storage record for subject #{subject_digest} in organization #{org.id}", common_log_fields("gh.org.id" => org.id, "gh.repo.attestation.subject_digest" => subject_digest))
      span.add_event("fetching storage records by org and subject digest", attributes: { "gh.repo.attestation.subject_digest" => subject_digest, "gh.org.id" => org.id })

      control_access :authenticated_user,
        resource: org,
        challenge: true,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      # First, find all artifact metadata IDs the actor has read access to
      approved_artifact_ids = fetch_metadata_record_ids_with_read_access!(org, subject_digest)

      # Then query only storage records for approved artifacts
      records = ArtifactStorageRecord.where(artifact_metadata_id: approved_artifact_ids).to_a

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

      GitHub.logger.info("Store artifact deployment record #{data} for organization #{org.id}", common_log_fields("gh.org.id" => org.id))
      symbolized_data = data.symbolize_keys
      tags = symbolized_data[:tags] || {}

      begin
        DeploymentRecordManager.validate_deployment_record_tags!(tags)
      rescue DeploymentRecordManager::ErrInvalidTag => e
        deliver_error!(400, message: e.message)
      end

      span.add_event("creating deployment record by org and subject digest", attributes: { "gh.repo.attestation.subject_digest" => symbolized_data[:digest], "gh.org.id" => org.id })

      repo_and_attestation_ids = fetch_repository_and_attestation_ids!(org, symbolized_data[:digest], symbolized_data[:github_repository])
      filtered = filter_repo_and_attestation_ids_by_write_access!(repo_and_attestation_ids, org)

      records = create_or_update_deployment_records!(org, data, filtered)
      records.each do |record|
        ArtifactRegistryHydroMessageManager.send_hydro_message_for_deployment_record(record)
      end

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

      GitHub.logger.info("Get artifact deployment records for subject #{subject_digest} in organization #{org.id}", common_log_fields("gh.org.id" => org.id, "gh.repo.attestation.subject_digest" => subject_digest))
      span.add_event("fetching deployment records by org and subject digest", attributes: { "gh.repo.attestation.subject_digest" => subject_digest, "gh.org.id" => org.id })

      # First, find all artifact metadata IDs the actor has read access to
      approved_artifact_ids = fetch_metadata_record_ids_with_read_access!(org, subject_digest)

      # Then query only deployment records for approved artifacts
      records = ArtifactDeploymentRecord.where(artifact_metadata_id: approved_artifact_ids).to_a

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

      # The cluster path parameter maximum length is not enforced automatically by the OpenAPI spec, so we validate it here
      cluster = params[:cluster]
      if cluster.length > 128
        deliver_error!(422, message: "Invalid request.\n\ncluster must be no longer than 128 characters")
      end

      GitHub.logger.info("Set cluster deployment records for organization #{org.id} with #{data}", common_log_fields("gh.org.id" => org.id))
      span.add_event("set deployment records by org and cluster", attributes: common_log_fields("gh.org.id" => org.id, "gh.cluster" => cluster))

      symbolized_data = data.symbolize_keys
      cluster = params[:cluster]
      logical_environment = symbolized_data[:logical_environment]
      physical_environment = symbolized_data[:physical_environment]
      deployments = symbolized_data[:deployments] || []

      deployment_manager = DeploymentRecordManager.new(org, cluster, logical_environment, physical_environment)
      begin
        deployment_manager.build_deployment_templates!(deployments)
      rescue DeploymentRecordManager::ErrConflictingDeploymentInfo,
              DeploymentRecordManager::ErrDuplicateDeploymentName,
              DeploymentRecordManager::ErrInvalidTag => e
        deliver_error!(400, message: e.message)
      end

      GitHub.logger.info("Cluster deployment parameters have been validated, attempting to set cluster deployment records", common_log_fields("gh.org.id" => org.id, "gh.cluster" => cluster))
      records = set_cluster_scoped_deployment_records!(org, deployment_manager)

      set_records = records[:set] || []
      decommissioned_records = records[:decommissioned] || []
      # Send Hydro messages for all modified deployment records asynchronously in a separate job to avoid increasing endpoint response time
      # It shouldn't be possible to reach this point in the logic if no records have bee created/updated or deleted
      # but this check ensures we don't enqueue the job if there are no records to process
      if set_records.any? || decommissioned_records.any?
        HydroDeploymentRecordStatusChangeJob.perform_later(records)
      end

      GitHub.logger.info("Cluster deployment records have been set successfully", common_log_fields("gh.org.id" => org.id, "record_count" => set_records.count))
      deliver :artifact_deployment_records_hash, { records: set_records, total_count: set_records.count }
    end
  end

  private

  # The larger Artifact Registry feature set is not supported on GHES
  def reject_on_ghes!
    if GitHub.single_tenant_enterprise?
      deliver_error! 404
    end
  end

  def common_log_fields(extra = {})
    {
      "http.route" => GitHub.context[:api_route],
      "gh.actor.name" => GitHub.context[:actor_name],
    }.merge(extra)
  end

  sig { params(org: Organization, digest: String).returns(T::Array[Integer]) }
  def fetch_metadata_record_ids_with_read_access!(org, digest)
    records = ArtifactMetadata
      .where(owner_id: org.id, digest: digest)
      .select(:id, :repository_id)
      .includes(:repository)

    # If the actor is app installed at the org level that has the read_artifact_metadata permission enabled on all repositories
    # return the record ids
    if access_allowed?(:read_org_artifact_metadata, resource: org, allow_integrations: true, allow_user_via_granular_actor: true)
      return records.map(&:id)
    end


    # Otherwise filter out records associated with repositories that do not have the permission granted
    records.filter_map do |record|
      record.id if access_allowed?(:read_artifact_metadata, resource: record.repository, allow_integrations: true, allow_user_via_granular_actor: true)
    end
  end

  def fetch_repository_and_attestation_ids!(org, digest, github_repo_name)
    begin
      ArtifactMetadataManager.get_repository_and_attestation_ids(org, digest, github_repo_name)
    rescue => e
      handle_artifact_metadata_errors!(e)
    end
  end

  sig { params(err: StandardError).void }
  def handle_artifact_metadata_errors!(err)
    case err
    when ArtifactMetadataManager::ErrMissingDigest
      GitHub.logger.error(err.message, common_log_fields)
      deliver_error! 403, message: "digest is required"
    when ArtifactMetadataManager::ErrNoArtifactsFound
      GitHub.logger.error(err.message, common_log_fields)
      deliver_error! 404, message: ERR_NO_ARTIFACTS_FOUND
    when ArtifactMetadataManager::ErrNoRepoAccess
      GitHub.logger.error(err.message, common_log_fields)
      deliver_error! 403, message: ERR_NO_ARTIFACTS_FOUND
    else
      deliver_error! 500, message: "Record creation failed"
    end
  end

  def get_storage_record_status(data)
    parsed_data = data.symbolize_keys
    status = ArtifactMetadata.statuses[parsed_data[:status].to_s.downcase]
    if status.nil?
      status = ArtifactMetadata.statuses[:active]
    end
    status
  end

  sig { params(org: Organization, data: T::Hash[T.any(Symbol, String), String], include_source_registry: T::Boolean).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def create_storage_records!(org, data, include_source_registry: false)
    parsed_data = data.symbolize_keys
    digest = parsed_data[:digest]
    github_repo_name = parsed_data[:github_repository]

    repo_and_attestation_ids = fetch_repository_and_attestation_ids!(org, digest, github_repo_name)
    filtered = filter_repo_and_attestation_ids_by_write_access!(repo_and_attestation_ids, org)

    storage_records = []
    begin
      # because the function expects:
      # 1. creating multiple artifact storage records
      # 2. the creation or update of existing artifact metadata records
      # it needs to account for potential failures when writing to the database for both cases.
      # Preload all existing ArtifactMetadata records for this org/digest/repository_id set
      repository_ids = filtered.map { |e| e[:repository_id] }.compact
      existing_artifacts = ArtifactMetadata.fetch_and_index_by_repo_id(org.id, digest, repository_ids)

      with_write(clusters: [ApplicationRecord::ArtifactRegistry]) do
        filtered.each do |entry|
          ArtifactMetadata.transaction do
            repository_id, attestation_id = entry.values_at(:repository_id, :attestation_id)
            artifact = existing_artifacts[T.must(repository_id)]
            artifact ||= ArtifactMetadata.create(org, parsed_data, T.must(repository_id), attestation_id)

            status = get_storage_record_status(parsed_data)
            artifact.update!(status: status)

            # Because we currently only want to store the source registry if it's explicitly
            # for a supported integration like JFrog Artifactory, we check that the include_source_registry parameter is set to true.
            # If not set to true, the source_registry field is not included.
            # The parameter defaults to false and must be explicitly set to true to write to the source_registry field.
            attrs = {
              artifact_path: parsed_data[:artifact_path],
              artifact_url: parsed_data[:artifact_url],
              deleted_at: (Time.now if status == ArtifactMetadata.statuses[:deleted]),
              registry_repository_name: parsed_data[:repository],
              registry_url: parsed_data[:registry_url],
              source_registry: (parsed_data[:source_registry] if include_source_registry),
              actor_id: current_actor&.id,
              integration_id: current_integration&.id,
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

              storage_records << storage_record.to_hash
            end
          end
        end
      end
    rescue => e
      GitHub.logger.error("Error creating storage records for organization #{org.id}: #{e.message}",
        common_log_fields("gh.org.id" => org.id)
      )
      deliver_error! 500
    end

    storage_records
  end

  sig { params(org: Organization, data: T::Hash[T.any(Symbol, String), String], repo_and_attestation_ids: T.nilable(T::Array[T::Hash[Symbol, T.untyped]])).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def create_or_update_deployment_records!(org, data, repo_and_attestation_ids)
    if repo_and_attestation_ids.blank?
      GitHub.logger.info("No repository and attestation linkages found for the provided deployment parameters, cannot create deployment record", common_log_fields("gh.org.id" => org.id))
      deliver_error!(404, message: ERR_NO_ARTIFACTS_FOUND)
    end

    parsed_data = data.symbolize_keys
    digest = parsed_data[:digest]

    GitHub.logger.info(
      "Creating or updating deployment records with #{repo_and_attestation_ids.length} repository and attestation linkages",
      common_log_fields("gh.org.id" => org.id, "gh.repo.attestation.subject_digest" => digest, "gh.repo.attestation.linkage_count" => repo_and_attestation_ids.length)
    )
    deployment_records = []
    begin
      # because the function expects:
      # 1. creating multiple artifact storage records
      # 2. the creation or update of existing artifact metadata records
      # it needs to account for potential failures when writing to the database for both cases.
      # Preload all existing ArtifactMetadata records for this org/digest/repository_id set
      repository_ids = repo_and_attestation_ids.map { |e| e[:repository_id] }.compact
      existing_artifacts = ArtifactMetadata.fetch_and_index_by_repo_id(org.id, digest, repository_ids)

      with_write(clusters: [ApplicationRecord::ArtifactRegistry]) do
        repo_and_attestation_ids.each do |entry|
          repository_id, attestation_id = entry.values_at(:repository_id, :attestation_id)
          ArtifactMetadata.transaction do
            artifact = existing_artifacts[repository_id]
            artifact ||= ArtifactMetadata.create(org, parsed_data, T.must(repository_id), attestation_id)

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
              deployment_record.update_all_tags(parsed_data[:tags], parsed_data[:runtime_risks])
            else
              tags, runtime_risks = parsed_data.values_at(:tags, :runtime_risks)
              deployment_record.update_event(artifact, tags, runtime_risks)
            end

            if parsed_data[:status] == STATUS_DECOMMISSIONED
              deployment_record.decommission
            end

            deliver_error!(422) if deployment_record.errors.any?
            deployment_records << deployment_record.to_hash
          end
        end
      end
    rescue => e
      GitHub.logger.error("Error creating deployment records for organization #{org.id}: #{e.message}",
        common_log_fields("gh.org.id" => org.id)
      )
      deliver_error! 500
    end

    deployment_records
  end

  sig { params(org: Organization, data: T::Hash[T.any(Symbol, String), String], repo_and_attestation_ids: T.nilable(T::Array[T::Hash[Symbol, T.untyped]])).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def create_deployment_records!(org, data, repo_and_attestation_ids)
    # skip creating records if no repository linkage is found
    return [] if repo_and_attestation_ids.blank?
    parsed_data = data.symbolize_keys
    digest = parsed_data[:digest]

    GitHub.logger.info("Creating deployment records with #{repo_and_attestation_ids.length} repository and attestation linkages", common_log_fields("gh.org.id" => org.id, "gh.repo.attestation.subject_digest" => digest, "gh.repo.attestation.linkage_count" => repo_and_attestation_ids.length))
    deployment_records = []
    begin
      # because the function expects:
      # 1. creating multiple artifact deployment records
      # 2. creating or updating existing artifact metadata records
      # it needs to account for potential failures when writing to the database for both cases.
      # Preload all existing ArtifactMetadata records for this cluster, logical env, physical env, and digest set
      repository_ids = repo_and_attestation_ids.map { |e| e[:repository_id] }
      existing_artifacts = ArtifactMetadata.fetch_and_index_by_repo_id(org.id, digest, repository_ids)

      with_write(clusters: [ApplicationRecord::ArtifactRegistry]) do
        repo_and_attestation_ids.each do |entry|
          repository_id, attestation_id = entry.values_at(:repository_id, :attestation_id)
          ArtifactMetadata.transaction do
            artifact = existing_artifacts[repository_id]
            artifact ||= ArtifactMetadata.create(org, parsed_data, T.must(repository_id), attestation_id)

            deployment_params = {
              logical_environment: parsed_data[:logical_environment],
              physical_environment: parsed_data[:physical_environment] || "",
              cluster: parsed_data[:cluster] || "",
              deployment_name: parsed_data[:deployment_name],
            }

            # repository_id must not be null
            repository_id = T.must(repository_id)
            deployment_record = ArtifactDeploymentRecord.record_by_deploy_params_and_repo(deployment_params, repository_id, deployed_status_only: true)
            nil_record = deployment_record.nil?

            if nil_record
              deployment_params[:artifact_metadata_id] = artifact.id
              deployment_params[:owner_id] = org.id
              deployment_record = ArtifactDeploymentRecord.create(deployment_params)
              deployment_record.update_all_tags(parsed_data[:tags], parsed_data[:runtime_risks])
            end

            deliver_error!(422) if deployment_record.errors.any?
            deployment_records << deployment_record.to_hash
          end
        end
      end
    rescue => e
      GitHub.logger.error("Error creating deployment records for organization #{org.id}: #{e.message}",
        common_log_fields("gh.org.id" => org.id)
      )
      deliver_error! 500
    end

    deployment_records
  end

  sig { params(org: Organization, templates: T::Array[DeploymentTemplate]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def create_deployment_records_in_bulk!(org, templates)
    now = Time.current

    # Extract all digests and repository IDs in a single pass
    all_digests = Set.new
    repository_ids = Set.new
    templates.each do |template|
      all_digests << template.artifact_template.digest
      T.must(template.linkage.repo_and_attestation_ids).each { |entry| repository_ids << entry[:repository_id] }
    end
    all_digests = all_digests.to_a.compact
    repository_ids = repository_ids.to_a.compact

    # Fetch existing artifact metadata record IDs and build inserts for missing ones in one pass over templates
    existing_artifact_ids = ArtifactMetadata.bulk_fetch_ids_by_digest_and_repo_id(org.id, all_digests, repository_ids)
    bulk_artifact_insert = templates.flat_map { |t| t.build_artifact_metadata_inserts(existing_artifact_ids, org.id, now) }
    bulk_artifact_insert.uniq! { |row| [row[:repository_id], row[:digest]] }

    begin
      with_write(clusters: [ApplicationRecord::ArtifactRegistry]) do
        ArtifactMetadata.transaction do
          # Bulk insert new artifact metadata records in a single query
          bulk_artifact_insert.each_slice(100) do |batch|
            ArtifactMetadata.insert_all(batch)
          end

          # Re-fetch all artifact metadata IDs to get IDs for newly inserted records
          all_artifact_ids = ArtifactMetadata.bulk_fetch_ids_by_digest_and_repo_id(org.id, all_digests, repository_ids)

          # Set artifact_metadata_id on templates that were missing it (newly inserted records)
          templates.each { |t| t.assign_artifact_metadata_ids!(all_artifact_ids, org.id) }

          # Build bulk insert for deployment records using the artifact_metadata_id from the templates
          bulk_deployment_record_insert = templates.flat_map(&:build_hashes_per_repo)

          bulk_deployment_record_insert.each_slice(100) do |batch|
            timestamped_batch = batch.map { |attrs| attrs.merge(created_at: now, updated_at: now) }
            ArtifactDeploymentRecord.insert_all(timestamped_batch)
          end

          # Fetch records to return them, scoped to cluster and environment to avoid false matches
          deployment_names = bulk_deployment_record_insert.map { |entry| entry[:deployment_name] }.uniq
          cluster = bulk_deployment_record_insert.first&.dig(:cluster)
          logical_environment = bulk_deployment_record_insert.first&.dig(:logical_environment)
          physical_environment = bulk_deployment_record_insert.first&.dig(:physical_environment)
          deployment_records = ArtifactDeploymentRecord.where(
            owner_id: org.id,
            deployment_name: deployment_names,
            cluster: cluster,
            logical_environment: logical_environment,
            physical_environment: physical_environment,
            deleted_at: nil,
          ).to_a

          # Bulk insert tags for all deployment records by deployment name
          # Multiple records can have the same deployment name with different artifact_metadata_ids (different repos)
          # All records with the same deployment name should get the tags from the matching template
          records_by_name = deployment_records.group_by { |record| record.deployment_name }
          bulk_tag_insert = templates.flat_map do |template|
            records = records_by_name[template.deployment_name]
            next [] if records.nil? || records.empty?
            records.flat_map { |record| template.build_tag_inserts(record.id, now) }
          end
          if bulk_tag_insert.any?
            bulk_tag_insert.each_slice(100) do |batch|
              ArtifactDeploymentRecordTag.insert_all(batch)
            end
          end

          deliver_error!(422) if deployment_records.any? { |record| record.errors.any? }
          return deployment_records.map(&:to_hash)
        end
      end
    rescue => e
      GitHub.logger.error("Error creating deployment records for organization #{org.id}: #{e.message}",
        common_log_fields("gh.org.id" => org.id)
      )
      deliver_error! 500
    end

    []
  end

  sig { params(org: Organization, templates: T::Array[DeploymentTemplate], current_records: T::Array[ArtifactDeploymentRecord]).returns(T.untyped) }
  def update_deployment_records_in_bulk!(org, templates, current_records)
    now = Time.current

    # Extract all digests and repository IDs in a single pass
    all_digests = Set.new
    repository_ids = Set.new
    templates.each do |template|
      all_digests << template.artifact_template.digest
      T.must(template.linkage.repo_and_attestation_ids).each { |entry| repository_ids << entry[:repository_id] }
    end
    all_digests = all_digests.to_a.compact
    repository_ids = repository_ids.to_a.compact

    # Fetch existing artifact metadata record IDs and build inserts for missing ones
    existing_artifact_ids = ArtifactMetadata.bulk_fetch_ids_by_digest_and_repo_id(org.id, all_digests, repository_ids)
    bulk_artifact_insert = templates.flat_map { |t| t.build_artifact_metadata_inserts(existing_artifact_ids, org.id, now) }

    # Index current records by deployment_name for fast lookup
    current_records_by_name = current_records.index_by(&:deployment_name)

    begin
      with_write(clusters: [ApplicationRecord::ArtifactRegistry]) do
        ArtifactMetadata.transaction do
          # Bulk insert new artifact metadata records
          bulk_artifact_insert.each_slice(100) do |batch|
            ArtifactMetadata.insert_all(batch)
          end

          # Re-fetch all artifact metadata IDs for newly inserted records
          all_artifact_ids = ArtifactMetadata.bulk_fetch_ids_by_digest_and_repo_id(org.id, all_digests, repository_ids)

          # Set artifact_metadata_id on templates
          templates.each { |t| t.assign_artifact_metadata_ids!(all_artifact_ids, org.id) }

          # Build upsert hashes with the existing record's id so upsert_all
          # matches on the primary key and updates in place
          record_ids = []
          bulk_deployment_record_upsert = templates.flat_map do |template|
            existing_record = current_records_by_name[template.deployment_name]
            next [] if existing_record.nil?

            record_ids << existing_record.id
            template.build_hashes_per_repo.map { |h| h.merge(id: existing_record.id, updated_at: now) }
          end

          # Bulk upsert deployment records using primary key for conflict resolution
          bulk_deployment_record_upsert.each_slice(100) do |batch|
            # rubocop:disable GitHub/UpsertAll
            ArtifactDeploymentRecord.upsert_all(batch)
          end

          # Bulk replace tags: delete existing tags then insert new ones
          ArtifactDeploymentRecordTag.where(deployment_record_id: record_ids).delete_all

          # Apply tags to all deployment records with matching deployment names
          # Multiple records can have the same deployment name with different artifact_metadata_ids
          records_by_name = current_records.group_by { |record| record.deployment_name }
          bulk_tag_insert = templates.flat_map do |template|
            records = records_by_name[template.deployment_name]
            next [] if records.nil? || records.empty?
            records.flat_map { |record| template.build_tag_inserts(record.id, now) }
          end
          if bulk_tag_insert.any?
            bulk_tag_insert.each_slice(100) do |batch|
              ArtifactDeploymentRecordTag.insert_all(batch)
            end
          end

          # Reload records to return them with updated state
          deployment_records = ArtifactDeploymentRecord.where(id: record_ids).to_a
          # Manually trigger the artifact metadata soft delete callback on the updated deployment
          # records since upsert_all bypasses callbacks
          deployment_records.each do |record|
            record.send(:check_artifact_standalone)
          end

          deliver_error!(422) if deployment_records.any? { |record| record.errors.any? }
          deployment_records.map(&:to_hash)
        end
      end
    rescue => e
      GitHub.logger.error("Error updating deployment records for organization #{org.id}: #{e.message}",
        common_log_fields("gh.org.id" => org.id)
      )
      deliver_error! 500
    end
  end

  sig { params(repo_and_attestation_ids: T::Array[T::Hash[Symbol, Integer]], org: Organization).returns(T::Array[T::Hash[Symbol, Integer]]) }
  def filter_repo_and_attestation_ids_by_write_access!(repo_and_attestation_ids, org)
    # For org-level GitHub App installations on all repos, check org-level permission once instead of per-repo
    # If the actor is app installed at the org level that has the read_artifact_metadata permission enabled on all repositories
    # return the record ids
    if access_allowed?(:write_org_artifact_metadata, resource: org, allow_integrations: true, allow_user_via_granular_actor: true)
      return repo_and_attestation_ids
    end

    # For users/OAuth and repo-level app installations, check per-repo permissions
    filtered = repo_and_attestation_ids.filter do |entry|
      repo = Repository.find_by(id: entry[:repository_id], owner_id: org.id)
      access_allowed?(:write_artifact_metadata, resource: repo, allow_integrations: true, allow_user_via_granular_actor: true)
    end
    if filtered.empty?
      deliver_error!(404, message: ERR_NO_ARTIFACTS_FOUND)
    end
    filtered
  end

  sig { params(org: Organization, repos: T::Array[Repository]).returns(T::Boolean) }
  def actor_has_artifact_metadata_write_access?(org, repos)
    # First check if the current_actor is an app installed at the organization level with the write_artifact_metadata
    # permission enabled against all repositories. This is the fast path that allows us to avoid checking permissions against each repository for org-level installations.
    return true if access_allowed?(:write_org_artifact_metadata, resource: org, allow_integrations: true, allow_user_via_granular_actor: true)

    # If the current_actor does not fit that criteria, then fallback to checking if permission is enabled across the provided repositories
    repos.all? { |repo| access_allowed?(:write_artifact_metadata, resource: repo, allow_integrations: true, allow_user_via_granular_actor: true) }
  end

  sig { params(records: T::Array[ArtifactDeploymentRecord], deployment_manager: DeploymentRecordManager, org: Organization).void }
  def check_all_record_permissions!(records, deployment_manager, org)
    repo_ids = records.map { |record| T.must(record.artifact_metadata).repository_id }.compact.uniq

    if deployment_manager.deployment_templates.present?
      new_record_linkage = []
      begin
        new_record_linkage = deployment_manager.set_artifact_linkage_and_return_repository_ids
      rescue => e
        handle_artifact_metadata_errors!(e)
      end

      # If no repo and attestation IDs are found for the provided deployments, we have not found a valid way to link
      # the proposed deployment records to artifacts and repositories
      if new_record_linkage.blank?
        GitHub.logger.info("No repository and attestation linkages found for the provided deployment parameters, cannot create deployment record", common_log_fields("gh.org.id" => org.id))
        deliver_error!(404, message: "no deployment records found")
      end
      # return the set union of elements to remove duplicates
      repo_ids |= Array(new_record_linkage)
    end
    unique_repo_ids = repo_ids.uniq

    # Check that the actor has the required permissions to create new deployment records
    # by verifying write access to all repositories associated with the found artifacts
    repos = Repository.where(id: unique_repo_ids, owner_id: org.id).to_a

    # Ensure that all repository IDs we intend to use actually resolve to repositories owned by this org.
    # If there is any mismatch, fail early so that missing or cross-org repositories cannot bypass authz
    # or data-integrity checks.
    if repos.size != unique_repo_ids.size
      GitHub.logger.info(
        "Mismatch between requested repositories and repositories belonging to org when creating deployment records",
        common_log_fields("gh.org.id" => org.id, "gh.requested_repo_ids" => repo_ids, "gh.found_repo_ids" => repos.pluck(:id))
      )
      deliver_error!(403, message: "insufficient access to create new deployment records")
    end

    unless actor_has_artifact_metadata_write_access?(org, repos)
      GitHub.logger.info("Actor does not have write access to repository for deployment record creation", common_log_fields("gh.org.id" => org.id))
      deliver_error!(403, message: "insufficient access to create new deployment records")
    end
  end

  sig { params(org: Organization, deployment_manager: DeploymentRecordManager).returns(T.untyped) }
  def set_cluster_scoped_deployment_records!(org, deployment_manager)
    cluster = deployment_manager.cluster
    logical_environment = deployment_manager.logical_environment
    physical_environment = deployment_manager.physical_environment

    GitHub.logger.info("Fetching current deployment records", common_log_fields("gh.org.id" => org.id, "gh.cluster" => cluster, "gh.logical_environment" => logical_environment, "gh.physical_environment" => physical_environment))
    # fetch current records by cluster, logical env, physical env
    current_cluster_records = ArtifactDeploymentRecord.records_with_cluster(logical_environment, physical_environment, cluster, org.id).to_a
    # check that the actor has the required permissions to update or decommission existing
    GitHub.logger.info("Checking permissions for existing deployment records", common_log_fields("gh.org.id" => org.id, "gh.cluster" => cluster))
    check_all_record_permissions!(current_cluster_records, deployment_manager, org)

    # the actor must have permissions to decommission all existing records and create all new records at this point
    cluster_record_state = deployment_manager.categorize_cluster_deployment_changes(current_cluster_records)

    to_decommission_records = cluster_record_state[:to_delete]
    to_decommission_ids = to_decommission_records.map(&:id)
    artifact_metadata_ids_to_delete = to_decommission_records.map(&:artifact_metadata_id)

    GitHub.logger.info(
      "Decommissioning #{to_decommission_ids.size} deployment records",
      common_log_fields("gh.org.id" => org.id, "gh.cluster" => cluster)
    )
    with_write(clusters: [ApplicationRecord::ArtifactRegistry]) do
      ArtifactDeploymentRecord.where(id: to_decommission_ids).update_all(deleted_at: Time.now)
    end

    # update existing records
    updated = []
    to_update = cluster_record_state[:to_update]
    if to_update.present?
      GitHub.logger.info("Updating #{to_update.size} deployment records", common_log_fields("gh.org.id" => org.id, "gh.cluster" => cluster))
      updated = updated.concat(update_deployment_records_in_bulk!(org, to_update, current_cluster_records))
    end

    # create records not in current set
    created = []
    to_create = cluster_record_state[:to_create]
    if to_create.present?
      GitHub.logger.info("Creating #{to_create.size} deployment records", common_log_fields("gh.org.id" => org.id, "gh.cluster" => cluster))
      created = created.concat(create_deployment_records_in_bulk!(org, to_create))
    end

    # Asynchronously soft delete any standalone artifact metadata records
    # associated with the decommissioned deployment records
    GitHub.logger.info(
      "Scheduling bulk soft delete for #{artifact_metadata_ids_to_delete.size} artifact metadata records",
      common_log_fields("gh.org.id" => org.id, "gh.cluster" => cluster)
    )
    ArtifactMetadataBulkSoftDeleteJob.perform_later(artifact_metadata_ids_to_delete) if artifact_metadata_ids_to_delete.present?

    # serialize decommissioned records to return later for Hydro messages
    serialized_decommissioned_records = to_decommission_records.map(&:to_hash)
    { set: created + updated.flatten, decommissioned: serialized_decommissioned_records }
  end
end
