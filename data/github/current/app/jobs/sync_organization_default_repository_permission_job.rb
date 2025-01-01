# typed: true
# frozen_string_literal: true

class SyncOrganizationDefaultRepositoryPermissionJob < ApplicationJob
  queue_as :sync_organization_default_repository_permission

  # This job could have been enqueued during a dependent destroy, in which
  # case the actor has already been deleted. In that case, just bail out
  # of the job.
  discard_on(ActiveRecord::RecordNotFound)

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  def self.status(target)
    JobStatus.find(SyncOrganizationDefaultRepositoryPermissionJob.job_id(target))
  end

  def self.enqueue(target, actor:)
    JobStatus.create(id: SyncOrganizationDefaultRepositoryPermissionJob.job_id(target), ttl: 4.hours)

    SyncOrganizationDefaultRepositoryPermissionJob.perform_later(target.id, target.class.name, actor.id)
  end

  def self.job_id(target)
    "sync-organization-default-repository-permissions-#{target.class.name.downcase}_#{target.id}"
  end

  def perform(target_id, target_name, actor_id, opts = {})
    actor = User.find(actor_id)
    target_type = target_name.present? ? target_name.constantize : ::Organization
    target = target_type.find(target_id)

    # the JobStatus won't exist for pre-queued upgrades from GHE < 2.15.0.
    # add a backup to create a job status if it doesn't exist.
    status = JobStatus.find(SyncOrganizationDefaultRepositoryPermissionJob.job_id(target)) ||
      JobStatus.create(id: SyncOrganizationDefaultRepositoryPermissionJob.job_id(target), ttl: 4.hours)

    log_fields = {
      "code.namespace" => "SyncOrganizationDefaultRepositoryPermissionJob",
    }
    if target.is_a?(Organization)
      log_fields.merge!({ "gh.organization" => target.display_login })
    elsif target.is_a?(Business)
      log_fields.merge!({ "gh.business.slug" => target.slug })
    end

    GitHub.logger.info(
      log_fields.merge!({ msg: "Starting default repository sync run" })
    )
    status.track do
      with_write { target.sync_default_repository_permission!(actor: actor) }
    end
    GitHub.logger.info(
      log_fields.merge!({ msg: "Ending default repository sync run" })
    )
  end
end
