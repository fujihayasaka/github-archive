# typed: strict
# frozen_string_literal: true

module Assignments
  module Public
    extend self
    extend T::Sig

    include Kernel

    # Transfer all assignments from one assignee (usually a mannequin) to another.
    sig { params(source: User, target: User).void }
    def transfer_to_assignee(source, target)
      owner = source.owner.owner
      # handle duplicate assignees for users who have this use case
      handle_duplicate_assignees = GitHub.flipper[:mannequin_claiming_duplicate_assignees].enabled?(target) || GitHub.flipper[:mannequin_claiming_duplicate_assignees].enabled?(owner)
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

      ::Assignment.where(assignee_id: source.id).update_all(assignee_id: target.id)
    end
  end
end
