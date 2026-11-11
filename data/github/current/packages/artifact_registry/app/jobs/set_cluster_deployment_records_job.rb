# typed: true
# frozen_string_literal: true

class SetClusterDeploymentRecordsJob < ApplicationJob
  queue_as :artifact_registry_cluster_jobs

  use_primaries ApplicationRecord::ArtifactRegistry

  BATCH_SIZE = 250
  RETRY_ATTEMPTS = 3

  retry_on_recoverable_exceptions
  retry_on_dirty_exit

  retry_on StandardError, wait: :polynomially_longer, attempts: RETRY_ATTEMPTS do |job, error|
    if job.executions >= RETRY_ATTEMPTS
      cluster_job = ArtifactClusterJob.find_by(id: job.arguments.first[:cluster_job_id])
      cluster_job&.mark_failed!(error.message)
    end
  end

  sig { params(cluster_job_id: Integer).void }
  def perform(cluster_job_id:)
    cluster_job = ArtifactClusterJob.find(cluster_job_id)
    return if cluster_job.status == "completed"

    cluster_job.mark_processing! unless cluster_job.status == "processing"
    enqueued_at = cluster_job.enqueued_at

    org = Organization.find(cluster_job.owner_id)
    accepted_deployments = cluster_job.accepted_deployments || []

    # Re-validate repo ownership (cheap indexed query — repos may have been
    # transferred or deleted between POST and job execution)
    repo_ids = accepted_deployments
      .flat_map { |d| (d["repo_and_attestation_ids"] || []).map { |r| r["repository_id"] } }
      .compact
      .uniq
    valid_repo_ids = Repository.where(id: repo_ids, owner_id: org.id).pluck(:id).to_set
    accepted_deployments, rejected = accepted_deployments.partition do |d|
      (d["repo_and_attestation_ids"] || []).all? { |r| valid_repo_ids.include?(r["repository_id"]) }
    end
    processing_errors = rejected.map { |d| { "cause" => "repo_no_longer_owned", "deployment_name" => d["deployment_name"] } }

    # Reconstruct DeploymentTemplate objects from serialized data
    templates = accepted_deployments.map { |d| reconstruct_template(d, cluster_job) }

    # Re-read current cluster state at execution time (fresh view)
    current_records = ArtifactDeploymentRecord
      .records_with_cluster(
        cluster_job.logical_environment,
        cluster_job.physical_environment,
        cluster_job.cluster,
        org.id,
      ).to_a

    # Categorize changes
    accepted_names = templates.map(&:deployment_name).to_set
    current_by_name = current_records.index_by(&:deployment_name)

    to_decommission = current_records.reject { |r| accepted_names.include?(r.deployment_name) }
    update_templates = templates.select { |t| current_by_name.key?(t.deployment_name) }
    create_templates = templates.reject { |t| current_by_name.key?(t.deployment_name) }

    updater = ClusterDeploymentUpdateManager.new(org, skip_records_updated_after: enqueued_at)

    total_mutated = 0
    all_artifact_metadata_ids_to_delete = []

    # Decommission records not in accepted set (skip records updated after enqueued_at)
    to_decommission.each_slice(BATCH_SIZE) do |batch|
      result = updater.decommission_records(batch)
      total_mutated += result[:count]
      all_artifact_metadata_ids_to_delete.concat(result[:artifact_metadata_ids])
    end

    # Update existing records
    update_templates.each_slice(BATCH_SIZE) do |batch|
      batch_records = batch.map { |t| current_by_name[t.deployment_name] }.compact
      result = updater.update_records(batch, batch_records)
      total_mutated += result.count
      all_artifact_metadata_ids_to_delete.concat(result.artifact_metadata_ids_to_delete)
    end

    # Create new records
    create_templates.each_slice(BATCH_SIZE) do |batch|
      result = updater.create_records(batch)
      total_mutated += result.count
    end

    # Enqueue follow-up jobs for cleanup
    if all_artifact_metadata_ids_to_delete.any?
      ArtifactMetadataBulkSoftDeleteJob.perform_later(all_artifact_metadata_ids_to_delete)
    end

    cluster_job.mark_completed!(
      count: total_mutated,
      job_errors: processing_errors.presence,
    )
  end

  private

  sig { params(deployment_hash: T::Hash[String, T.untyped], cluster_job: ArtifactClusterJob).returns(DeploymentTemplate) }
  def reconstruct_template(deployment_hash, cluster_job)
    artifact_template = ArtifactTemplate.new(
      digest: deployment_hash["digest"],
      name: deployment_hash["name"],
      version: deployment_hash["version"],
    )
    template = DeploymentTemplate.new(cluster_job.owner_id, artifact_template, {
      cluster: cluster_job.cluster,
      deployment_name: deployment_hash["deployment_name"],
      logical_environment: cluster_job.logical_environment,
      physical_environment: cluster_job.physical_environment,
      runtime_risks: deployment_hash["runtime_risks"] || [],
      tags: (deployment_hash["tags"] || {}).symbolize_keys,
      status: deployment_hash["status"] || "deployed",
    })
    template.linkage.repo_and_attestation_ids = (deployment_hash["repo_and_attestation_ids"] || []).map do |r|
      { repository_id: r["repository_id"], attestation_id: r["attestation_id"], artifact_metadata_id: nil }
    end
    template
  end
end
