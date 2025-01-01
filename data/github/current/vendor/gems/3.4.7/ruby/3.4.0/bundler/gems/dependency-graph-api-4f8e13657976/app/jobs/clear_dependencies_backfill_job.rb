# frozen_string_literal: true

# This job deletes the manifst data related to the given repository
# It uses the same logic as ClearDependenciesJob, but is enqueued to a different
# queue in order to avoid the backfill from blocking the regular clear dependencies
# job.
class ClearDependenciesBackfillJob < ClearDependenciesJob
  queue_as :dg_disabling_backfill

  def is_backfill?
    true
  end
end
