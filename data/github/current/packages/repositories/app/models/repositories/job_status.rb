# typed: strict
# frozen_string_literal: true

module Repositories
  class JobStatus < ::JobStatus
    include ::JobStatus::Context

    sig { returns(T::Array[T.untyped]) }
    def self.tracked_jobs
      [
        BulkRepositoryRestoreJob,
        Stafftools::DisableRepositoryAccessStatus,
        RepositoryNetworkGraphBuilderJob,
      ].freeze
    end

    sig { params(id: String).returns(T::Boolean) }
    def self.handles_id?(id)
      tracked_jobs.any? { |job| id.start_with?(job.prefix) }
    end

    sig { returns(GitHub::KV) }
    def self.kv_store
      Repositories::Kv.store
    end
  end
end
