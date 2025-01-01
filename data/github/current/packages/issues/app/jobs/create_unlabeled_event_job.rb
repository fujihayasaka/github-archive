# typed: true
# frozen_string_literal: true

# to replace inline writes of Label.unlabel_associated_issues
class CreateUnlabeledEventJob < ApplicationJob
  queue_as :create_unlabeled_event_job

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  def perform(actor_id, issue_ids, unlabeled_at, label_id, label_name, label_color)
    actor = User.find_by(id: actor_id) || User.ghost

    # constructing a label model for convenience
    # the label will no longer exist in the DB when the job is executed
    label = Label.new \
      id: label_id,
      name: label_name,
      color: label_color

    issue_id = issue_ids.pop

    with_write do
      if issue = Issue.find_by(id: issue_id)
        unless issue.events.find_by(event: "unlabeled", created_at: unlabeled_at, issue_event_details: { label_id: label_id })
          Issue.throttle_with_retry do
            issue.transaction do
              issue.events.create \
                event: "unlabeled",
                actor: actor,
                label: label,
                created_at: unlabeled_at

              issue.touch
            end
          end
        end
      end
    end

    CreateUnlabeledEventJob.perform_later(actor_id, issue_ids, unlabeled_at, label_id, label_name, label_color) if issue_ids.any?
  end
end
