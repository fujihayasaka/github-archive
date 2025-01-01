# typed: true
# frozen_string_literal: true

class Api::OrganizationArtifactsMetadata < Api::App
  ERR_NO_ARTIFACTS_FOUND = "no artifacts found"
  STATUS_DECOMMISSIONED = "decommissioned"

  post "/organizations/:organization_id/artifacts/metadata/storage-record", operation_id: "orgs/create-artifact-storage-record", read_from_replicas: true do
    GitHub.tracer.in_span("Api::OrganizationArtifactsMetadata#create_storage_record", kind: :internal) do |span|
      org = find_org!
      ensure_artifact_metadata_api_feature_flag_enabled!(org)

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
      if !FeatureFlag.vexi.enabled?(:jfrog_artifactory_storage_record, org, default: false)
        deliver_error! 404
      end

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
      org = find_org!
      ensure_artifact_metadata_api_feature_flag_enabled!(org)
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
      org = find_org!
      ensure_deployment_record_api_feature_flag_enabled!(org)

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
      span.add_event("creating deployment record by org and subject digest", attributes: { "gh.repo.attestation.subject_digest" => symbolized_data[:digest], "gh.org.id" => org.id })

      records = create_deployment_records!(org, data)
      deliver :artifact_deployment_records_hash, { records: records, total_count: records.count }
    end
  end

  get "/organizations/:organization_id/artifacts/:subject_digest/metadata/deployment-records", operation_id: "orgs/list-artifact-deployment-records" do
    GitHub.tracer.in_span("Api::OrganizationArtifactsMetadata#get_deployment_records", kind: :internal) do |span|
      org = find_org!
      ensure_deployment_record_api_feature_flag_enabled!(org)

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

  private

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

  sig { params(actor: T.untyped).void }
  def ensure_artifact_metadata_api_feature_flag_enabled!(actor)
    if !FeatureFlag.vexi.enabled?(:artifact_metadata_api, actor, default: false)
      deliver_error! 404
    end
  end

  def ensure_deployment_record_api_feature_flag_enabled!(actor)
    if !FeatureFlag.vexi.enabled?(:deployment_record_api, actor, default: false)
      deliver_error! 404
    end
  end

  sig { params(org: Organization, digest: String).returns(T.untyped) }
  def find_provenance_attestations_from_digest_and_org!(org, digest)
    # we need to find repositories that have a provenance attestation with the given digest
    response = TrustMetadata.list_attestations_by_owner_subject_digest(org, digest, predicate_type: "provenance")
    if !response.call_succeeded?
      if response.status == 404
        Rails.logger.error("No provenance attestations for organization #{org.id} with digest #{digest} found")
        deliver_error!(404, message: ERR_NO_ARTIFACTS_FOUND)
      end
      Rails.logger.error("call to TMA with org #{org.id} and digest #{digest} failed")
      deliver_error! 500
    end

    if response.value.nil? || response.value.attestations.empty?
      Rails.logger.error("No provenance attestations for organization #{org.id} with digest #{digest} found")
      deliver_error!(404, message: ERR_NO_ARTIFACTS_FOUND)
    end

    filtered = response.value.attestations.filter do |attestation|
      repo = Repository.find_by(id: attestation.repository_id, owner_id: org.id)
      access_allowed?(:write_artifact_metadata, resource: repo, allow_integrations: true, allow_user_via_granular_actor: true)
    end
    deliver_error! 404 if filtered.empty?

    filtered
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
    attestations = find_provenance_attestations_from_digest_and_org!(org, digest)

    storage_records = []
    begin
      # because the function expects:
      # 1. creating multiple artifact storage records
      # 2. the creation or update of existing artifact metadata records
      # it needs to account for potential failures when writing to the database for both cases.
      # Preload all existing ArtifactMetadata records for this org/digest/repository_id set
      repository_ids = attestations.map(&:repository_id)
      existing_artifacts = ArtifactMetadata.where(
        owner_id: org.id,
        digest: digest,
        repository_id: repository_ids
      ).index_by(&:repository_id)

      with_write(clusters: [ApplicationRecord::ArtifactRegistry]) do
        attestations.each do |attestation|
          ArtifactMetadata.transaction do
            artifact = existing_artifacts[attestation.repository_id]
            unless artifact
              artifact = ArtifactMetadata.create!(
                owner_id: org.id,
                digest: digest,
                repository_id: attestation.repository_id,
                attestation_id: attestation.id,
                name: parsed_data[:name],
                version: parsed_data[:version]
              )
              existing_artifacts[attestation.repository_id] = artifact
            end

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
  def create_deployment_records!(org, data)
    parsed_data = data.symbolize_keys
    digest = parsed_data[:digest]
    attestations = find_provenance_attestations_from_digest_and_org!(org, digest)

    deployment_records = []
    begin
      # because the function expects:
      # 1. creating multiple artifact storage records
      # 2. the creation or update of existing artifact metadata records
      # it needs to account for potential failures when writing to the database for both cases.
      # Preload all existing ArtifactMetadata records for this org/digest/repository_id set
      repository_ids = attestations.map(&:repository_id)
      existing_artifacts = ArtifactMetadata.where(
        owner_id: org.id,
        digest: digest,
        repository_id: repository_ids
      ).index_by(&:repository_id)

      with_write(clusters: [ApplicationRecord::ArtifactRegistry]) do
        attestations.each do |attestation|
          ArtifactMetadata.transaction do
            artifact = existing_artifacts[attestation.repository_id]
            unless artifact
              artifact = ArtifactMetadata.create!(
                owner_id: org.id,
                digest: digest,
                repository_id: attestation.repository_id,
                attestation_id: attestation.id,
                name: parsed_data[:name],
                version: parsed_data[:version]
              )
              existing_artifacts[attestation.repository_id] = artifact
            end

            deployment_params = {
              logical_environment: parsed_data[:logical_environment],
              physical_environment: parsed_data[:physical_environment] || "",
              cluster: parsed_data[:cluster] || "",
              deployment_name: parsed_data[:deployment_name]
            }

            deployment_record = ArtifactDeploymentRecord.find_by(deployment_params)
            nil_record = deployment_record.nil?

            if nil_record
              deployment_params[:artifact_metadata_id] = artifact.id
              deployment_record = ArtifactDeploymentRecord.create(deployment_params)
              send_hydro_message_for_deployment_record("artifacts_metadata.artifact_deployment_record.create", deployment_record)
            elsif deployment_record.artifact_metadata != artifact
              old_artifact = deployment_record.artifact_metadata
              deployment_record.update(artifact_metadata: artifact)
              old_artifact.soft_delete if old_artifact&.standalone?
            end

            deployment_record.update_tags(parsed_data[:tags])
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
