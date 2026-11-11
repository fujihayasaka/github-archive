# typed: strict
# frozen_string_literal: true

module Assignments
  module Public
    TRANSFERABLE_BATCH_LIMIT = 100

    extend self

    # Transfer all assignments from one assignee (usually a mannequin) to another.
    sig { params(source: User, target: User).void }
    def transfer_to_assignee(source, target)
      owner = source.owner.owner
      # handle duplicate assignees for users who have this use case
      handle_duplicate_assignees = FeatureFlag.vexi.enabled?(:mannequin_claiming_duplicate_assignees, target, owner, default: false)
      if handle_duplicate_assignees
        ::Assignment.where(assignee_id: source.id).each do |assignment|
          # check to see if assignment already exists
          if Assignment.where(assignee_id: target.id, issue_id: assignment.issue_id).exists?

            GitHub.logger.error("Could not rewrite all associations of assignments", {
              "code.function": "duplicate_assignment_association",
              "gh.migration_tools.transferable.assignment.issue_id": assignment.issue_id,
              "gh.migration_tools.transferable.assignment.target_id": target.id,
              "gh.migration_tools.transferable.assignment.source_id": source.id,
              }
            )
            # delete mannequin assignment
            assignment.destroy
          else
            assignment.update_columns(assignee_id: target.id)
          end
        end
        return
      end

      if FeatureFlag.vexi.enabled?(:octoshift_mannequin_reclaiming_in_batches, default: false)
        ::Assignment.where(assignee_id: source.id).in_batches(of: TRANSFERABLE_BATCH_LIMIT) do |batch|
          ::Assignment.throttle { batch.update_all(assignee_id: target.id) }
        end
      else
        ::Assignment.where(assignee_id: source.id).update_all(assignee_id: target.id)
      end
    end
  end
end
