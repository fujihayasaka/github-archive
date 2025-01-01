# typed: true
# frozen_string_literal: true

# to replace inline writes of Label.unlabel_associated_issues
class DestroyIssuesLabelsJob < ApplicationJob
  queue_as :destroy_issues_labels_job

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  def perform(actor_id, unlabeled_at, label_id, label_name, label_color, repository_id)
    create_unlabeled_events(actor_id, unlabeled_at, label_id, label_name, label_color, repository_id)
    DestroyDependentRecordsJob.perform_later(Label.name, label_id, :issues_labels, sharding_key: :repository_id , sharding_value: repository_id)
  end

  def create_unlabeled_events(actor_id, unlabeled_at, label_id, label_name, label_color, repository_id)
    # 99th is ~100, MAX is over 2 million
    # Using repository_id here so Vitess can use it to route the request to the correct shard.
    # Without it label_id is used, but was already deleted from label_id_ks_idx after the label was destroyed,
    # resulting in the IssueLabel record not being found.
    issue_ids = IssuesLabels.where(label_id: label_id, repository_id: repository_id)
      .joins(:issue)
      .where(issue: { state: "open" })
      .distinct
      .pluck(:issue_id)
    if issue_ids.any?
      issue_ids.in_groups_of(100, false) do |grouped_issue_ids|
        CreateUnlabeledEventJob.perform_later(
          actor_id,
          grouped_issue_ids,
          unlabeled_at,
          label_id,
          label_name,
          label_color
        )
      end
    end
  end
end
