# typed: true
# frozen_string_literal: true

module MemexProject::ArchivalDependency
  extend ActiveSupport::Concern
  extend T::Helpers
  include GitHub::Memoizer

  requires_ancestor { MemexProject }

  sig { params(viewer: User, items: T::Array[MemexProjectItem]).returns(T.nilable(JobStatus)) }
  def archive_job(viewer:, items:)
    return nil if !self.persisted? || items.empty?

    job_status = MemexArchiveJob.create_job_status
    MemexArchiveJob.perform_later(job_status.id, items, viewer.id, self.id, request_context: GitHub.context.to_hash)

    job_status
  end

  sig { params(viewer: User, item_ids: T::Array[Integer]).returns(T.nilable(JobStatus)) }
  def unarchive_project_items_later(viewer:, item_ids:)
    return nil if !self.persisted? || item_ids.empty?

    job_status = MemexUnarchiveItemsJob.create_job_status
    MemexUnarchiveItemsJob.perform_later(job_status.id, item_ids, viewer.id, self.id, request_context: GitHub.context.to_hash)

    job_status
  end
end
