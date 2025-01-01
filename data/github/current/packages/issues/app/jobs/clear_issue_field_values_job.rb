# typed: strict
# frozen_string_literal: true

# A backround job that clears issue field values that are set to a specific issue field option.
# Useful when an issue field option is deleted and we want to clear all values that are set to it.
class ClearIssueFieldValuesJob < BatchedJob
  use_primaries ApplicationRecord::IssuesPullRequests

  queue_as :clear_issue_field_values

  BATCH_SIZE = T.let(1000.freeze, Integer)

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  sig { params(issue_field_id: T.nilable(Integer), issue_field_option_id: T.nilable(Integer)).void }
  def perform(issue_field_id:, issue_field_option_id:)
    return unless issue_field_option_id
    return unless issue_field_id

    issue_field_values_ids = IssueFieldValue
      .where(issue_field_id: issue_field_id)
      .where(data_type: :single_select)
      .where("JSON_TYPE(value) = 'INTEGER' AND value = #{issue_field_option_id}")
      .pluck(:id)

    issue_field_values_ids.each_slice(BATCH_SIZE) do |issue_field_value_batch|
      with_write do
        IssueFieldValue.where(id: issue_field_value_batch).update_all(value: nil)
      end
    end
  end
end
