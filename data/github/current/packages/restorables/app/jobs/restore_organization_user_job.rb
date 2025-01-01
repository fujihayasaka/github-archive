# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class RestoreOrganizationUserJob < ApplicationJob
  queue_as :restore_organization_user

  # Hash lock to prevent multiple jobs for the same Restorable::OrganizationUser being enqueued concurrently.
  locked_by timeout: 1.minute, key: ->(job) {
    hash = job.arguments[0]
    options = hash.with_indifferent_access
    options.fetch("restorable_organization_user_id")
  }

  retry_on_dirty_exit

  resolve_tenant_context do |options|
    options = options.with_indifferent_access
    restorable_organization_user_id = options.fetch("restorable_organization_user_id")
    restorable_organization_user = Restorable::OrganizationUser.find(restorable_organization_user_id)
    org = restorable_organization_user.organization
    org&.business
  end

  # Capture all exceptions (this should include any library or application exceptions)
  rescue_from ::StandardError do |error|
    Failbot.report!(error)
    raise error
  end

  # Public: Queue restore job.
  #
  # restorable_organization_user - The Restorable::OrganizationUser object.
  def self.enqueue(restorable_organization_user:, actor:)
    RestoreOrganizationUserJob.perform_later({
      restorable_organization_user_id: restorable_organization_user.id,
      actor_id: actor.id
    })
  end

  def self.prefix
    "restorable"
  end

  def self.job_id(user)
    "#{prefix}_#{user.id}"
  end

  # Public: Perform job to restore organization user.
  #
  # options - Hash with "restorable_organization_user_id" and "status_id" keys.
  def perform(options)
    options = options.with_indifferent_access
    restorable_organization_user_id = options.fetch("restorable_organization_user_id")
    restorable_organization_user = Restorable::OrganizationUser.find(restorable_organization_user_id)
    actor = User.find(options.fetch("actor_id"))

    status = Organization::JobStatus.find(RestoreOrganizationUserJob.job_id(restorable_organization_user))
    return unless status.present?

    status.track do
      with_write { restorable_organization_user.restore(actor: actor) }
    end
  end
end
