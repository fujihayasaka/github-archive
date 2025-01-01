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

  sig { returns(Integer) }
  memoize def archived_items_limit
    # This method is not intended to be used in conjunction with pwl single limit.
    # For more details, see: https://github.com/github/projects-platform/issues/2974
    if memex_table_without_limits_or_pwl_public_beta_enabled?
      MemexProjectItem::EXPANDED_ARCHIVED_ITEM_LIMIT
    else
      MemexProjectItem::ARCHIVED_ITEM_LIMIT
    end
  end

  sig { returns(T::Boolean) }
  def would_exceed_limit_to_archive_existing_item?
    if memex_table_without_limits_or_pwl_public_beta_enabled?
      false # Moving existing item to archive doesn't impact single limit
    else
      memex_project_items.archived.count >= archived_items_limit
    end
  end

  sig { params(viewer: User, item_ids: T::Array[Integer]).returns(T.nilable(JobStatus)) }
  def unarchive_project_items_later(viewer:, item_ids:)
    return nil if !self.persisted? || item_ids.empty?

    job_status = MemexUnarchiveItemsJob.create_job_status
    MemexUnarchiveItemsJob.perform_later(job_status.id, item_ids, viewer.id, self.id, request_context: GitHub.context.to_hash)

    job_status
  end
end
