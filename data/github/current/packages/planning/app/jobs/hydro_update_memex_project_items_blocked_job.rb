# typed: true
# frozen_string_literal: true

class HydroUpdateMemexProjectItemsBlockedJob < HydroMessageJob
  queue_as :hydro_update_memex_project_items_blocked
  retry_on_dirty_exit

  sig { void }
  def perform
    return unless topic == "github.v1.IssueDependencyListRecalculate"

    issue_id = T.let(message.dig(:issue, :id), T.nilable(Integer))
    repository_id = T.let(message.dig(:repository, :id), T.nilable(Integer))
    # counts set to 0 by default if not present
    blocked_by_count = T.let(message.dig(:blocked_by), Integer)
    blocking_count = T.let(message.dig(:blocking), Integer)

    return unless issue_id.present? && repository_id.present?

    memex_projects_items = MemexProjectItem.where(repository_id:, issue_id:)

    with_write do
      memex_projects_items.update_all(
        blocked_by_count: blocked_by_count,
        blocking_count: blocking_count,
      )
    end if memex_projects_items.any?
  end
end
