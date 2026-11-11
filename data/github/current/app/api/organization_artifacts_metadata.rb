# typed: true
# frozen_string_literal: true

class Api::OrganizationArtifactsMetadata < Api::App
  include Api::App::ArtifactMetadataPermissionsHelper

  ERR_NO_ARTIFACTS_FOUND = "no artifacts found"
  ERR_INSUFFICIENT_ACCESS = "artifact metadata write permission required on one or more repositories"
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
      return_records = symbolized_data.fetch(:return_records, true)
      span.add_event("creating storage records by org and subject digest", attributes: { "gh.repo.attestation.subject_digest" => symbolized_data[:digest], "gh.org.id" => org.id })

      records = create_storage_records!(org, data)

      ArtifactRegistryHydroMessageManager.send_hydro_messages_for_storage_records(records)

      new_data = if return_records
        { total_count: records.length, records: records }
      else
        { total_count: records.length, records: nil }
      end
      deliver :artifact_storage_records_hash, new_data
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

      deliver_404_error! unless records.any?

      deliver :artifact_storage_records_hash, { records: records, total_count: records.size }
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
      return_records = symbolized_data.fetch(:return_records, true)

      begin
        DeploymentTemplateManager.validate_deployment_record_tags!(tags)
      rescue DeploymentTemplateManager::ErrInvalidTag => e
        deliver_error!(400, message: e.message)
      end

      span.add_event("creating deployment record by org and subject digest", attributes: { "gh.repo.attestation.subject_digest" => symbolized_data[:digest], "gh.org.id" => org.id })

      repo_and_attestation_ids = T.must(fetch_repository_and_attestation_ids!(org, symbolized_data[:digest], symbolized_data[:github_repository]))
      filtered = filter_repo_and_attestation_ids_by_write_access!(repo_and_attestation_ids, org)

      records = create_or_update_deployment_records!(org, data, filtered)
      records.each do |record|
        ArtifactRegistryHydroMessageManager.send_hydro_message_for_deployment_record(record)
      end

      new_record_data = if return_records
        { total_count: records.length, records: records }
      else
        { total_count: records.length, records: nil }
      end
      deliver :artifact_deployment_records_hash, new_record_data
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

      deliver_404_error! unless records.any?

      deliver :artifact_deployment_records_hash, { records: records, total_count: records.size }
    end
  end

  post "/organizations/:organization_id/artifacts/metadata/deployment-record/cluster/:cluster", operation_id: "orgs/set-cluster-deployment-records", read_from_replicas: true do
    GitHub.tracer.in_span("Api::OrganizationArtifactsMetadata#set_cluster_deployment_records", kind: :internal) do |span|
      # Track request start time for response time metrics
      request_start_time = GitHub::Dogstats.monotonic_time

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
      logical_environment = symbolized_data[:logical_environment]
      physical_environment = symbolized_data[:physical_environment]
      deployments = symbolized_data[:deployments] || []
      return_records = symbolized_data.fetch(:return_records, true)

      # partial_success functionality is currently only available behind a feature flag
      partial_success = if FeatureFlag.vexi.enabled?("set_cluster_records_partial_success", org, default: false)
        symbolized_data.fetch(:partial_success, false)
      else
        false
      end

      # Track request body metrics
      deployment_count = deployments.size
      request_body_size = request.content_length.to_i

      metrics = SetClusterRecordMetrics.new(deployment_count)

      metrics.publish_distribution_metric("request_body_size", request_body_size)
      metrics.publish_distribution_metric("deployment_count", deployment_count)

      deployment_template_manager = DeploymentTemplateManager.new(org, cluster, logical_environment, physical_environment)
      begin
        deployment_template_manager.build_deployment_templates!(deployments, metrics)
      rescue DeploymentTemplateManager::ErrDuplicateDeploymentName,
              DeploymentTemplateManager::ErrInvalidTag => e
        deliver_error!(400, message: e.message)
      end

      status = "error"

      begin
        GitHub.logger.info("Fetching current deployment records", common_log_fields("gh.org.id" => org.id, "gh.cluster" => cluster, "gh.logical_environment" => logical_environment, "gh.physical_environment" => physical_environment))
        # fetch current records by cluster, logical env, physical env
        current_cluster_records = ArtifactDeploymentRecord.records_with_cluster(logical_environment, physical_environment, cluster, org.id).to_a

        # check that the actor has the required permissions to update or decommission existing
        GitHub.logger.info("Checking permissions for existing deployment records", common_log_fields("gh.org.id" => org.id, "gh.cluster" => cluster))
        permission_start = GitHub::Dogstats.monotonic_time
        authorization_result = begin
          authorize_cluster_set_records!(current_cluster_records, deployment_template_manager, partial_success, metrics)
        rescue => e
          deliver_artifact_metadata_errors!(e, partial_success)
          return
        end
        metrics.publish_distribution_metric("permission_handling_time", GitHub::Dogstats.duration(permission_start))

        cluster_deployment_manager = ClusterDeploymentManager.new(cluster, authorization_result)
        GitHub.logger.info("Cluster deployment parameters have been validated, attempting to set cluster deployment records", common_log_fields("gh.org.id" => org.id, "gh.cluster" => cluster))

        records = set_cluster_scoped_deployment_records!(org, cluster_deployment_manager, metrics)

        set_records = records[:set] || []

        # If all deployment templates have a GitHub repository parameter and there are set records,
        # enqueue a job to set the provenance attestation for the created/updated artifact metadata records
        if deployment_template_manager.can_defer_tma_call && set_records.present?
          created_updated_artifact_metadata_ids = T.let(Set.new, T::Set[Integer])
          set_records.each { |record| created_updated_artifact_metadata_ids.add(record[:artifact_metadata_id]) }
          GitHub.logger.info("Enqueuing SetArtifactProvenanceAttestationJob for artifact metadata IDs #{created_updated_artifact_metadata_ids.to_a}", common_log_fields("gh.org.id" => org.id))
          SetArtifactProvenanceAttestationJob.perform_later(ids: created_updated_artifact_metadata_ids.to_a)
        end

        decommissioned_records = records[:decommissioned] || []
        # Send Hydro messages for all modified deployment records asynchronously in a separate job to avoid increasing endpoint response time
        # It shouldn't be possible to reach this point in the logic if no records have bee created/updated or deleted
        # but this check ensures we don't enqueue the job if there are no records to process
        if set_records.any? || decommissioned_records.any?
          HydroDeploymentRecordStatusChangeJob.perform_later(records)
        end

        status = "success"
        GitHub.logger.info("Cluster deployment records have been set successfully", common_log_fields("gh.org.id" => org.id, "record_count" => set_records.count))

        errors = cluster_deployment_manager.build_error_response
        build_and_deliver_set_cluster_response(set_records, errors, return_records)
      ensure
        response_time_ms =
          if defined?(request_start_time)
            GitHub::Dogstats.duration(request_start_time)
          else
            0
          end

        status_tag = "status:#{status}"
        metrics.publish_distribution_metric("response_time", response_time_ms, [status_tag])
      end
    end
  end

  # Async cluster deployment record update - creates a background job
  post "/organizations/:organization_id/artifacts/metadata/deployment-record/cluster/:cluster/jobs", operation_id: "orgs/create-cluster-deployment-records-job", read_from_replicas: true do
    GitHub.tracer.in_span("Api::OrganizationArtifactsMetadata#create_cluster_deployment_records_job", kind: :internal) do |span|
      reject_on_ghes!
      org = find_org!

      unless FeatureFlag.vexi.enabled?("artifact_registry_async_cluster_jobs", org, default: false)
        deliver_error! 404
      end

      control_access :authenticated_user,
        resource: org,
        challenge: true,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      data = receive_with_openapi

      cluster = params[:cluster]
      if cluster.length > 128
        deliver_error!(422, message: "Invalid request.\n\ncluster must be no longer than 128 characters")
      end

      symbolized_data = data.symbolize_keys
      logical_environment = symbolized_data[:logical_environment]
      physical_environment = symbolized_data[:physical_environment] || ""
      deployments = symbolized_data[:deployments] || []

      if logical_environment.present? && logical_environment.length > 128
        deliver_error!(422, message: "Invalid request.\n\nlogical_environment must be no longer than 128 characters")
      end

      if physical_environment.present? && physical_environment.length > 128
        deliver_error!(422, message: "Invalid request.\n\nphysical_environment must be no longer than 128 characters")
      end

      deployment_count = deployments.size
      metrics = SetClusterRecordMetrics.new(deployment_count)

      # Validation: parse + dedup
      deployment_template_manager = DeploymentTemplateManager.new(org, cluster, logical_environment, physical_environment)
      begin
        deployment_template_manager.build_deployment_templates!(deployments, metrics)
      rescue DeploymentTemplateManager::ErrDuplicateDeploymentName,
              DeploymentTemplateManager::ErrInvalidTag => e
        deliver_error!(400, message: e.message)
      end

      # Fetch current records + authorize (always uses partial success semantics)
      current_cluster_records = ArtifactDeploymentRecord
        .records_with_cluster(logical_environment, physical_environment, cluster, org.id).to_a

      authorization_result = begin
        authorize_cluster_set_records!(current_cluster_records, deployment_template_manager, true, metrics)
      rescue => e
        deliver_artifact_metadata_errors!(e, true)
        return
      end

      # Build the deployment manager to get error response for rejected deployments
      cluster_deployment_manager = ClusterDeploymentManager.new(cluster, authorization_result)
      errors = cluster_deployment_manager.build_error_response

      # Serialize authorized templates with resolved linkage for the job
      authorized_templates = authorization_result.authorized.proposed_records

      if authorized_templates.empty?
        deliver_error!(403, message: "no repositories authorized")
      end

      accepted_deployments = authorized_templates.map do |template|
        {
          deployment_name: template.deployment_name,
          digest: template.artifact_template.digest,
          name: template.artifact_template.name,
          version: template.artifact_template.version,
          runtime_risks: template.runtime_risks,
          tags: template.tags,
          status: template.status,
          repo_and_attestation_ids: template.linkage.repo_and_attestation_ids&.map do |entry|
            { repository_id: entry[:repository_id], attestation_id: entry[:attestation_id] }
          end,
        }
      end

      # Use write connection for stale cleanup, concurrency check, and job creation
      # to avoid replication lag allowing duplicate jobs
      cluster_job = T.let(nil, T.nilable(ArtifactClusterJob))
      with_write(clusters: [ApplicationRecord::ArtifactRegistry]) do
        # Clean up stale jobs that have been pending/processing for too long
        cluster_scope = ArtifactClusterJob.for_cluster(org.id, cluster, logical_environment, physical_environment)
        stale_cutoff = ArtifactClusterJob::STALE_JOB_THRESHOLD.ago
        stale_jobs = cluster_scope.where(status: %w[pending processing]).where("created_at <= ?", stale_cutoff)
        stale_jobs.find_each { |job| job.mark_failed!("job timed out") }

        # Concurrency check: reject if there's an active (non-stale) job.
        # Note: currently there is a small race condition where concurrent POSTs can create duplicate jobs.
        # This is a tradeoff we are accepting for now because the state will self-heal at the next non-concurrent
        # request. However, in the future we can introduce a DB-level lock to prevent this if it is problematic in
        # practice.
        existing_job = cluster_scope
          .where(status: %w[pending processing])
          .order(created_at: :desc)
          .first
        if existing_job
          deliver_error!(409, message: "A job is already in progress for this cluster (job_id: #{existing_job.id})")
        end

        # Create job record
        enqueued_at = Time.now.utc
        cluster_job = ArtifactClusterJob.create!(
          owner_id: org.id,
          actor_id: current_actor&.id,
          integration_id: current_integration&.id,
          cluster: cluster,
          logical_environment: logical_environment,
          physical_environment: physical_environment,
          status: "pending",
          accepted_deployments: accepted_deployments,
          enqueued_at: enqueued_at,
        )
      end
      cluster_job = T.must(cluster_job)

      # Enqueue background job. If enqueueing fails, mark the job as failed
      # so it doesn't permanently block new submissions for this cluster.
      begin
        SetClusterDeploymentRecordsJob.perform_later(cluster_job_id: cluster_job.id)
      rescue => e
        cluster_job.mark_failed!("Failed to enqueue job: #{e.message}")
        deliver_error! 500
      end

      span.add_event("created cluster deployment records job", attributes: common_log_fields(
        "gh.org.id" => org.id,
        "gh.cluster" => cluster,
        "gh.job_id" => cluster_job.id,
        "gh.deployment_count" => deployment_count,
        "gh.authorized_count" => authorized_templates.size,
      ))

      GitHub.logger.info(
        "Created cluster deployment records job #{cluster_job.id}",
        common_log_fields("gh.org.id" => org.id, "gh.cluster" => cluster, "gh.job_id" => cluster_job.id),
      )

      # Return 202 with job ID + any permission errors
      response_data = { job_id: cluster_job.id }
      response_data[:errors] = errors if errors.present?
      deliver_raw(response_data, status: 202)
    end
  end

  # Get status of an async cluster deployment records job
  get "/organizations/:organization_id/artifacts/metadata/deployment-record/cluster/:cluster/jobs/:job_id",
      operation_id: "orgs/get-cluster-deployment-records-job" do
    reject_on_ghes!
    org = find_org!

    unless FeatureFlag.vexi.enabled?("artifact_registry_async_cluster_jobs", org, default: false)
      deliver_error! 404
    end

    control_access :authenticated_user,
      resource: org,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    cluster_job = ArtifactClusterJob.find_by(id: params[:job_id], owner_id: org.id, cluster: params[:cluster])
    unless cluster_job
      deliver_error!(404, message: "Not Found")
    end

    response_data = { job_id: cluster_job.id, status: cluster_job.status }

    case cluster_job.status
    when "pending"
      # No additional fields — job is waiting to be picked up
    when "processing"
      response_data[:started_at] = cluster_job.started_at
    when "completed"
      response_data[:started_at] = cluster_job.started_at
      response_data[:total_count] = cluster_job.total_count
      response_data[:errors] = cluster_job.job_errors if cluster_job.job_errors.present?
    when "failed"
      response_data[:started_at] = cluster_job.started_at
      response_data[:errors] = cluster_job.job_errors if cluster_job.job_errors.present?
    end

    deliver_raw(response_data)
  end

  private

  # The larger Artifact Registry feature set is not supported on GHES
  def reject_on_ghes!
    if GitHub.single_tenant_enterprise?
      deliver_error! 404
    end
  end

  sig { params(set_records: T::Array[T::Hash[String, T.untyped]], errors: T::Array[ClusterDeploymentManager::ErrorEntry], return_records: T::Boolean).void }
  def build_and_deliver_set_cluster_response(set_records, errors, return_records)
    resp = { total_count: set_records.length, errors: errors }
    response_data = if return_records
      resp.merge({ records: set_records })
    else
      resp.merge({ records: nil })
    end

    # Return 207 Multi-Status if there are errors in the response, otherwise 200
    http_status = response_data[:errors].present? ? 207 : 200
    deliver :artifact_deployment_records_hash, response_data, status: http_status
  end

  def common_log_fields(extra = {})
    {
      "http.route" => GitHub.context[:api_route],
      "gh.actor.name" => GitHub.context[:actor_name],
    }.merge(extra)
  end

  sig { params(message: T.any(String, Api::App::ArtifactMetadataPermissionsHelper::RepoErrorResponse)).void }
  def deliver_403_error!(message: "permission denied")
    deliver_error! 403, message: message
  end

  sig { params(errors: ActiveModel::Errors).returns(String) }
  def build_length_validation_error_message(errors)
    messages = errors.details.filter_map do |field, details|
      detail = details.first
      next unless detail[:error] == :too_long && detail[:count]

      "#{field} must be no longer than #{detail[:count]} characters"
    end

    return "Invalid request" if messages.empty?

    "Invalid request.\n\n#{messages.join(', ')}"
  end

  sig { params(message: T.any(String, T::Hash[String, T.untyped], Api::App::ArtifactMetadataPermissionsHelper::RepoErrorResponse)).void }
  def deliver_404_error!(message: ERR_NO_ARTIFACTS_FOUND)
    deliver_error! 404, message: message
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
      deliver_artifact_metadata_errors!(e)
    end
  end

  sig { params(err: StandardError, partial_success: T::Boolean).void }
  def deliver_artifact_metadata_errors!(err, partial_success = false)
    case err
    when ArtifactMetadataManager::ErrMissingDigest
      deliver_error! 400, message: "digest is required"
    when ArtifactMetadataPermissionsHelper::ErrTokenMissingWriteArtifactMetadataPerm,
          ArtifactMetadataPermissionsHelper::ErrNoRepositoryWriteAccess
      deliver_403_error!(message: err.response_message)
    when ArtifactMetadataPermissionsHelper::ErrNoDeploymentsAuthorized
      deliver_403_error!(message: "no repositories authorized")
    when ArtifactMetadataManager::ErrNoArtifactsFound
      deliver_404_error!
    when ArtifactMetadataManager::ErrRepositoryNotFound
      deliver_404_error!(message: "repository not found")
    when DeploymentTemplateManager::ErrRepositoryNotFound,
          ArtifactMetadataPermissionsHelper::ErrMismatchingRepositories,
          ArtifactMetadataPermissionsHelper::ErrNoArtifactLinkage,
          ArtifactMetadataPermissionsHelper::ErrNoReposFoundInOrg
      # When partial_success is enabled, return simplified error message
      # This check should be temporary. I would like to always return the simplified
      # "no repositories found" message when no repositories are found but I first want to get
      # feedback for the customer that they are happy with this simplified response before
      # always returning it
      message = if partial_success
        "no repositories found"
      else
        err.respond_to?(:response_message) ? err.response_message : "no repositories found"
      end
      deliver_404_error!(message: message)
    when ArtifactMetadataPermissionsHelper::ErrNoRepositoriesVisible,
          ArtifactMetadataPermissionsHelper::ErrNoRepoReadAccess,
          ArtifactMetadataPermissionsHelper::ErrNoDeploymentsFound
      deliver_404_error!(message: "no repositories found")
    when ArtifactMetadataManager::ErrTrustMetadata,
          ArtifactMetadataManager::ErrUnexpectedBulkResponse
      deliver_error! 500, message: "Record creation failed"
    else
      GitHub.logger.error("Error checking repository permissions for deployment record creation: #{err.message}")
      deliver_error!(500, message: "server error")
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

  sig { params(org: Organization, data: T::Hash[T.any(Symbol, String), String]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def create_storage_records!(org, data)
    parsed_data = data.symbolize_keys
    digest = parsed_data[:digest]
    github_repo_name = parsed_data[:github_repository]

    repo_and_attestation_ids = T.must(fetch_repository_and_attestation_ids!(org, digest, github_repo_name))
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
            artifact ||= ArtifactMetadata.find_or_create_by_digest!(org, parsed_data, T.must(repository_id), attestation_id)

            status = get_storage_record_status(parsed_data)
            artifact.update!(status: status)

            attrs = {
              artifact_path: parsed_data[:artifact_path],
              artifact_url: parsed_data[:artifact_url],
              deleted_at: (Time.now if status == ArtifactMetadata.statuses[:deleted]),
              registry_repository_name: parsed_data[:repository],
              registry_url: parsed_data[:registry_url],
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
    rescue ActiveRecord::RecordInvalid => e
      GitHub.logger.warn("Validation error creating storage records for organization #{org.id}",
        common_log_fields("gh.org.id" => org.id, "errors" => e.record.errors.to_hash)
      )
      deliver_error! 422, message: build_length_validation_error_message(e.record.errors)
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
      deliver_404_error!
    end

    parsed_data = data.symbolize_keys
    digest = parsed_data[:digest]

    GitHub.logger.info(
      "Creating or updating deployment records with #{T.must(repo_and_attestation_ids).length} repository and attestation linkages",
      common_log_fields("gh.org.id" => org.id, "gh.repo.attestation.subject_digest" => digest, "gh.repo.attestation.linkage_count" => T.must(repo_and_attestation_ids).length)
    )
    deployment_records = []
    begin
      # because the function expects:
      # 1. creating multiple artifact storage records
      # 2. the creation or update of existing artifact metadata records
      # it needs to account for potential failures when writing to the database for both cases.
      # Preload all existing ArtifactMetadata records for this org/digest/repository_id set
      repository_ids = T.must(repo_and_attestation_ids).map { |e| e[:repository_id] }.compact
      existing_artifacts = ArtifactMetadata.fetch_and_index_by_repo_id(org.id, digest, repository_ids)

      with_write(clusters: [ApplicationRecord::ArtifactRegistry]) do
        T.must(repo_and_attestation_ids).each do |entry|
          repository_id, attestation_id = entry.values_at(:repository_id, :attestation_id)
          ArtifactMetadata.transaction do
            artifact = existing_artifacts[repository_id]
            artifact ||= ArtifactMetadata.find_or_create_by_digest!(org, parsed_data, repository_id, attestation_id)

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
            else
              deployment_record.deploy
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

    GitHub.logger.info("Creating deployment records with #{T.must(repo_and_attestation_ids).length} repository and attestation linkages", common_log_fields("gh.org.id" => org.id, "gh.repo.attestation.subject_digest" => digest, "gh.repo.attestation.linkage_count" => T.must(repo_and_attestation_ids).length))
    deployment_records = []
    begin
      # because the function expects:
      # 1. creating multiple artifact deployment records
      # 2. creating or updating existing artifact metadata records
      # it needs to account for potential failures when writing to the database for both cases.
      # Preload all existing ArtifactMetadata records for this cluster, logical env, physical env, and digest set
      repository_ids = repo_and_attestation_ids.map { |e| T.must(e[:repository_id]) }
      existing_artifacts = ArtifactMetadata.fetch_and_index_by_repo_id(org.id, digest, repository_ids)

      with_write(clusters: [ApplicationRecord::ArtifactRegistry]) do
        repo_and_attestation_ids.each do |entry|
          repository_id, attestation_id = entry.values_at(:repository_id, :attestation_id)
          ArtifactMetadata.transaction do
            artifact = existing_artifacts[repository_id]
            artifact ||= ArtifactMetadata.find_or_create_by_digest!(org, parsed_data, repository_id, attestation_id)

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

    begin
      ArtifactMetadata.transaction do
        # Fetch existing artifact metadata record IDs and build inserts for missing ones in one pass over templates
        existing_artifact_ids = T.let({}, ArtifactMetadata::ArtifactIdsByRepositoryDigest)
        with_write(clusters: [ApplicationRecord::ArtifactRegistry]) do
          existing_artifact_ids = ArtifactMetadata.fetch_all_artifact_ids_by_digest_and_repo_id(org.id, all_digests, repository_ids)
        end
        bulk_artifact_insert = templates.flat_map { |t| t.build_artifact_metadata_inserts(existing_artifact_ids, org.id, now) }
        bulk_artifact_insert.uniq! { |row| [row[:repository_id], row[:digest]] }

        with_write(clusters: [ApplicationRecord::ArtifactRegistry]) do
          # Bulk insert new artifact metadata records in a single query
          bulk_artifact_insert.each_slice(100) do |batch|
            ArtifactMetadata.insert_all(batch)
          end

          # Only re-fetch if we inserted new records; otherwise use existing IDs
          all_artifact_ids = if bulk_artifact_insert.any?
            ArtifactMetadata.fetch_active_ids_by_digest_and_repo_id(org.id, all_digests, repository_ids)
          else
            existing_artifact_ids
          end

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
    rescue ActiveRecord::RecordNotFound => e
      GitHub.logger.info("Unable to revive soft deleted artifact metadata for organization #{org.id}: #{e.message}",
        common_log_fields("gh.org.id" => org.id)
      )
      deliver_404_error!(message: "repository not found")
    rescue => e
      GitHub.logger.error("Error creating deployment records for organization #{org.id}: #{e.message}",
        common_log_fields("gh.org.id" => org.id)
      )
      deliver_error! 500
    end
  end

  sig { params(org: Organization, templates: T::Array[DeploymentTemplate], current_records: T::Array[ArtifactDeploymentRecord]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
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

    begin
      artifact_metadata_ids_to_delete = T.let([], T::Array[Integer])
      updated_records = T.let([], T::Array[T::Hash[Symbol, T.untyped]])
      ArtifactMetadata.transaction do
        # Fetch existing artifact metadata record IDs and build inserts for missing ones
        # fetch_all_artifact_ids_by_digest_and_repo_id handles reviving soft-deleted records, so wrap with write access
        existing_artifact_ids = T.let({}, ArtifactMetadata::ArtifactIdsByRepositoryDigest)
        with_write(clusters: [ApplicationRecord::ArtifactRegistry]) do
          existing_artifact_ids = ArtifactMetadata.fetch_all_artifact_ids_by_digest_and_repo_id(org.id, all_digests, repository_ids)
        end
        bulk_artifact_insert = templates.flat_map { |t| t.build_artifact_metadata_inserts(existing_artifact_ids, org.id, now) }

        # Index current records by deployment_name for fast lookup
        current_records_by_name = current_records.index_by(&:deployment_name)

        record_ids = T.let([], T::Array[Integer])

        # Capture old artifact metadata IDs before upsert
        old_artifact_metadata_ids = Set.new(current_records.map(&:artifact_metadata_id).compact)
        with_write(clusters: [ApplicationRecord::ArtifactRegistry]) do
          # Bulk insert new artifact metadata records
          bulk_artifact_insert.each_slice(100) do |batch|
            ArtifactMetadata.insert_all(batch)
          end

          # Only re-fetch if we inserted new records; otherwise use existing IDs
          all_artifact_ids = if bulk_artifact_insert.any?
            ArtifactMetadata.fetch_active_ids_by_digest_and_repo_id(org.id, all_digests, repository_ids)
          else
            existing_artifact_ids
          end

          # Set artifact_metadata_id on templates
          templates.each { |t| t.assign_artifact_metadata_ids!(all_artifact_ids, org.id) }

          # Build upsert hashes with the existing record's id so upsert_all
          # matches on the primary key and updates in place
          bulk_deployment_record_upsert = templates.flat_map do |template|
            existing_record = current_records_by_name[template.deployment_name]
            next [] if existing_record.nil?

            record_ids << existing_record.id
            template.build_hashes_per_repo.map { |h| h.merge(id: existing_record.id, updated_at: now) }
          end

          # Sort by ID to ensure consistent lock ordering across concurrent operations
          # This prevents deadlocks when multiple requests are made for the same records
          sorted_upsert = bulk_deployment_record_upsert.sort_by { |h| h[:id] }
          sorted_upsert.each_slice(50) do |batch|
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

          updated_records = ArtifactDeploymentRecord.where(id: record_ids).map(&:to_hash)

          # Determine which artifact metadata IDs are no longer referenced
          new_artifact_metadata_ids = Set.new(updated_records.map { |r| r[:artifact_metadata_id] }.compact)
          artifact_metadata_ids_to_delete = (old_artifact_metadata_ids - new_artifact_metadata_ids).to_a
        end
      end
    rescue ActiveRecord::RecordNotFound => e
      GitHub.logger.info("Unable to revive soft deleted artifact metadata for organization #{org.id}: #{e.message}",
        common_log_fields("gh.org.id" => org.id)
      )
      deliver_404_error!(message: "repository not found")
    rescue => e
      GitHub.logger.error("Error updating deployment records for organization #{org.id}: #{e.message}",
        common_log_fields("gh.org.id" => org.id)
      )
      deliver_error! 500
    end

    # Asynchronously soft delete any artifact metadata records that are no longer referenced
    ArtifactMetadataBulkSoftDeleteJob.perform_later(artifact_metadata_ids_to_delete) if artifact_metadata_ids_to_delete.present?

    T.must(updated_records)
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
      deliver_404_error!
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

  sig { params(org: Organization, cluster_deployment_manager: ClusterDeploymentManager, metrics: SetClusterRecordMetrics).returns(T.untyped) }
  def set_cluster_scoped_deployment_records!(org, cluster_deployment_manager, metrics)
    # Detect deployment name conflicts
    # Conflicts occur when user has lost access to original repo but tries to update deployment to point to new repo
    # Actors should not be able to update records they no longer have write access to, even if they have access to the
    # new repository. This is a security measure to prevent actors from hijacking existing deployment records.
    cluster_deployment_manager.detect_deployment_name_conflicts

    cluster = cluster_deployment_manager.cluster
    categorize_start = GitHub::Dogstats.monotonic_time
    cluster_record_state = cluster_deployment_manager.categorize_cluster_deployment_changes
    metrics.publish_distribution_metric("categorize_records_time", GitHub::Dogstats.duration(categorize_start))

    to_decommission_records = cluster_record_state.to_delete
    to_decommission_ids = to_decommission_records.map(&:id)
    artifact_metadata_ids_to_delete = to_decommission_records.map(&:artifact_metadata_id)

    GitHub.logger.info(
      "Decommissioning #{to_decommission_ids.size} deployment records",
      common_log_fields("gh.org.id" => org.id, "gh.cluster" => cluster)
    )
    delete_start = GitHub::Dogstats.monotonic_time
    with_write(clusters: [ApplicationRecord::ArtifactRegistry]) do
      ArtifactDeploymentRecord.where(id: to_decommission_ids).update_all(deleted_at: Time.now)
    end
    metrics.publish_distribution_metric("delete_records_time", GitHub::Dogstats.duration(delete_start))

    # update existing records
    to_update = cluster_record_state.to_update
    update_start = GitHub::Dogstats.monotonic_time
    updated = if to_update.present?
      GitHub.logger.info("Updating #{to_update.size} deployment records", common_log_fields("gh.org.id" => org.id, "gh.cluster" => cluster))
      update_deployment_records_in_bulk!(org, to_update, cluster_deployment_manager.authorized_records)
    else
      []
    end
    metrics.publish_distribution_metric("update_records_time", GitHub::Dogstats.duration(update_start))

    # create records not in current set
    to_create = cluster_record_state.to_create
    create_start = GitHub::Dogstats.monotonic_time
    created = if to_create.present?
      GitHub.logger.info("Creating #{to_create.size} deployment records", common_log_fields("gh.org.id" => org.id, "gh.cluster" => cluster))
      create_deployment_records_in_bulk!(org, to_create)
    else
      []
    end
    metrics.publish_distribution_metric("create_records_time", GitHub::Dogstats.duration(create_start))

    # Asynchronously soft delete any standalone artifact metadata records
    # associated with the decommissioned deployment records
    GitHub.logger.info(
      "Scheduling bulk soft delete for #{artifact_metadata_ids_to_delete.size} artifact metadata records",
      common_log_fields("gh.org.id" => org.id, "gh.cluster" => cluster)
    )
    ArtifactMetadataBulkSoftDeleteJob.perform_later(artifact_metadata_ids_to_delete) if artifact_metadata_ids_to_delete.present?

    # serialize decommissioned records to return later for Hydro messages
    serialized_decommissioned_records = to_decommission_records.map(&:to_hash)
    {
      decommissioned: serialized_decommissioned_records,
      set: created + updated.flatten,
    }
  end
end
