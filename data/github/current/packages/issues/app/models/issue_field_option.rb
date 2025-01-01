# typed: strict
# frozen_string_literal: true

class IssueFieldOption < ApplicationRecord::Domain::IssuesPullRequests
  include Issues::IIssueFieldOption
  include GitHub::UTF8
  include GitHub::Validations

  COLORS = T.let({
    gray: 0,
    blue: 1,
    green: 2,
    yellow: 3,
    orange: 4,
    red: 5,
    pink: 6,
    purple: 7,
  }.freeze, T::Hash[Symbol, Integer])

  enum :color, COLORS, prefix: true, validate: true

  belongs_to :owner, class_name: "User", required: true
  belongs_to :issue_field, required: true
  validates :name, uniqueness: { scope: :issue_field_id, case_sensitive: false }
  validate :issue_field_must_be_single_select

  # After an option is destroyed, we queue a background job to find
  # and clear all issue field values that are set to this option.
  after_destroy_commit :clear_associated_issue_field_values # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  sig { returns(String) }
  def platform_type_name
    "IssueFieldSingleSelectOption"
  end

  private

  sig { void }
  def issue_field_must_be_single_select
    return unless issue_field

    unless T.must(issue_field).data_type_single_select?
      errors.add(:issue_field, :invalid_data_type, data_type: "single_select")
    end
  end

  sig { void }
  def clear_associated_issue_field_values
    ClearIssueFieldValuesJob.perform_later(issue_field_id: issue_field_id, issue_field_option_id: id)
  end
end
