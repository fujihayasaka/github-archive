# typed: true
# frozen_string_literal: true

module Milestone::PrioritizationDependency
  extend T::Helpers

  requires_ancestor { Milestone }

  # Overrides has_many relationship to pull a list in default priority order
  # for a milestone that has not been prioritized yet.
  def prioritized_issues(*attrs)
    self.reload if persisted?

    # If there is a discrepancy between the open_issues_count and the actual count of open issues, we need to update the milestone count
    if open_issue_count != issues.open_issues.count
      GitHub.dogstats.increment("milestone.bad_priority")
      SyncIssueCountsForMilestoneJob.perform_later(id: self.id)
    end

    # We cant use `prioritized?` because it returns true without `counter_cache` being passed, which prevents us from returning the issues in the default order
    return super unless self.issue_priorities.empty?
    issues.open_issues.reorder("id DESC")
  end

  # Does this milestone need to be backfilled?  True if the milestone has open
  # issues (other than this one) that aren't prioritized yet.
  def needs_backfill?(issue: nil)
    return false if prioritized?

    if issue
      prioritized_issue_ids = issue_priorities.where("issue_id <> ?", issue.id).pluck(:issue_id).sort
      open_issue_ids = issues.open_issues.where("id <> ?", issue.id).pluck(:id).sort

      prioritized_issue_ids != open_issue_ids
    else
      issues.open_issues.size > 0
    end
  end

  def prioritize_dependent!(issue, **options)
    if needs_backfill?(issue: issue) || issue.closed?
      false
    else
      super
    end
  end
  alias :prioritize_issue! :prioritize_dependent!

  # Populate an existing milestone with issue_priorities for all open issues.
  #
  #   force - Boolean flag that will clear out all existing IssuePriorities
  #           for this milestone and re-populate them from scratch
  #
  # Returns an Integer value of how many issue_priority records were created
  # or nothing if this milestone is inelegible for prioritization.
  def backfill!(force: false)
    return if prioritized? && !force

    affected_rows = 0

    GitHub.dogstats.time "prioritize_issue.time", tags: ["action:backfill_priorities"] do
      transaction do
        old_ids = issue_priorities.pluck(:id)

        if old_ids.any?
          while old_ids.any?
            IssuePriority.throttle do
              old_ids_slice = old_ids.shift(100)
              IssuePriority.connection.delete(Arel.sql(<<-SQL, ids: old_ids_slice, milestone_id: self.id))
                DELETE FROM issue_priorities
                WHERE milestone_id = :milestone_id AND id IN (:ids)
              SQL
            end
          end

          reload
        end

        if issues.open_issues.any?
          now = Time.current.to_formatted_s(:db)
          rows = []
          issues.open_issues.order(:created_at).pluck(:id, :repository_id, :created_at).map { |i| [i[0], i[1]] }
            .each_with_index do |(issue_id, repository_id), index|
            priority = index * GitHub::Prioritizable::GAP_SIZE + GitHub::Prioritizable::START_VALUE
            rows << [
              self.id,  # milestone_id
              issue_id, # issue_id
              priority, # priority
              now,      # created_at
              now,       # updated_at
              repository_id # repository_id
            ]
          end

          safe_table   = T.unsafe(self.class).connection.quote_table_name(IssuePriority.table_name)
          safe_columns = %w[milestone_id issue_id priority created_at updated_at repository_id].map do |name|
            T.unsafe(self.class).connection.quote_column_name(name)
          end.join(", ")

          while rows.any?
            rows_slice = rows.shift(100)

            affected_rows += IssuePriority.connection.update(Arel.sql(<<-SQL, rows: Arel::Nodes::ValuesList.new(rows_slice)))
              INSERT INTO #{safe_table} (#{safe_columns}) :rows
            SQL
          end
        end
      end
    end

    affected_rows
  end
end
