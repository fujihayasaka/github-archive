# typed: strict
# frozen_string_literal: true

class Organization
  class JobStatus < ::JobStatus
    include ::JobStatus::Context

    sig { returns(T::Array[T.untyped]) }
    def self.tracked_jobs
      [
        EnforceTwoFactorRequirementOnOrganizationJob,
        Organizations::ArchiveJob,
        RestoreOrganizationUserJob,
        SyncOrganizationDefaultRepositoryPermissionJob,
      ].freeze
    end

    sig { params(id: String).returns(T::Boolean) }
    def self.handles_id?(id)
      tracked_jobs.any? { |job| id.start_with?(job.prefix) }
    end

    sig { returns(GitHub::KV) }
    def self.kv_store
      Organization::KV.store
    end
  end
end
