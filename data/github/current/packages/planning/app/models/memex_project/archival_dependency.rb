# typed: true
# frozen_string_literal: true

module MemexProject::ArchivalDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { MemexProject }

  sig { params(viewer: User, items: T::Array[MemexProjectItem]).returns(T.nilable(JobStatus)) }
  def archive_job(viewer:, items:)
    return nil if !self.persisted? || items.empty?

    job_status = MemexArchiveJob.create_job_status
    MemexArchiveJob.perform_later(job_status.id, items, viewer.id, self.id, request_context: GitHub.context.to_hash)

    job_status
  end

  sig { returns(Integer) }
  def archived_items_limit
    memex_paginated_archive_enabled? ? MemexProjectItem::EXPANDED_ARCHIVED_ITEM_LIMIT : MemexProjectItem::ARCHIVED_ITEM_LIMIT
  end

  sig { returns(T::Boolean) }
  def has_reached_archived_items_limit?
    memex_project_items.archived.count >= archived_items_limit
  end

  # Returns true if either memex_table_without_limits or memex_paginated_archive are enabled for this project,
  # or if memex_paginated_archive is enabled for the project owner.
  sig { returns(T::Boolean) }
  def memex_paginated_archive_enabled?
    return @is_memex_paginated_archive_enabled if defined?(@is_memex_paginated_archive_enabled)
    @is_memex_paginated_archive_enabled = !GitHub.flipper[:memex_without_limits_kill_switch].enabled? && (
      self.memex_table_without_limits_or_pwl_public_beta_enabled? ||
      self.feature_enabled?(:memex_paginated_archive, memoize: false) ||
      owner&.feature_enabled?(:memex_paginated_archive) || false
    )
  end

  sig { params(viewer: User, item_ids: T::Array[Integer]).returns(T.nilable(JobStatus)) }
  def unarchive_project_items_later(viewer:, item_ids:)
    return nil if !self.persisted? || item_ids.empty?

    job_status = MemexUnarchiveItemsJob.create_job_status
    MemexUnarchiveItemsJob.perform_later(job_status.id, item_ids, viewer.id, self.id, request_context: GitHub.context.to_hash)

    job_status
  end
end
