# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: false
# frozen_string_literal: true

class PurgeRestorablesJob < ApplicationJob
  queue_as :purge_restorables
  schedule interval: 1.day
  locked_by timeout: 1.hour, key: ->(job) { job.class.name }

  retry_on_dirty_exit

  # There's no danger of cross-tenant leakage here.
  # We're only deleting records that are already tenant-scoped.
  exempt_from_tenant_context_requirement

  # purge records one day earlier than Archived Repository Records
  def expiration_period
    Time.now - ::RepositoryBulkPurgeJob.expiration_period + 1.day
  end

  def self.models
    @models ||= begin
      models = [
        Restorable::OrganizationUser,
        Restorable::TypeState,
        Restorable::Membership,
        Restorable::Repository,
        Restorable::RepositoryStar,
        Restorable::WatchedRepository,
        Restorable::IssueAssignment,
      ]
      models << Restorable::LdapTeamSyncUser if GitHub.enterprise?
      models
    end
  end

  # Public: Purges Restorable records older than EXPIRATION_PERIOD
  def perform(expiration: nil)
    expiration ||= expiration_period
    Restorable.where("created_at < ?", expiration).find_in_batches do |restorables|
      self.class.models.each do |model|
        delete_dependent_records(model, restorables)
      end

      # Remove Restorable records at the end to ensure the dependents aren't abandoned
      GitHub.dogstats.histogram "restorable.purged_records", restorables.count
      Restorable.throttle_writes do
        Restorable.where(id: restorables.map(&:id)).delete_all
      end
    end
  end

  def delete_dependent_records(model, restorables)
    model.where(restorable_id: restorables.map(&:id)).find_in_batches do |batch|
      GitHub.dogstats.histogram "restorable.purged_records", batch.count
      model.throttle_writes do
        model.where(id: batch.map(&:id)).delete_all
      end
    end
  end
end
