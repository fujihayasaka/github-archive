# typed: strict
# frozen_string_literal: true

class IssueFieldValue < ApplicationRecord::Domain::IssuesPullRequests
  include Issues::IIssueFieldValue
  include GitHub::UTF8
  include GitHub::Validations

  self.inheritance_column = :data_type

  sig { params(type_name: String).returns(T.any(T.class_of(IssueFieldTextValue), T.class_of(IssueFieldSingleSelectValue))) }
  def self.sti_class_for(type_name)
    case type_name
    when IssueFieldTextValue.sti_name
      IssueFieldTextValue
    when IssueFieldSingleSelectValue.sti_name
      IssueFieldSingleSelectValue
    else
      raise "Unknown issue field type: #{type_name}"
    end
  end

  # Associations
  belongs_to :issue_field, required: true
  belongs_to :issue, required: true
  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain
  belongs_to :actor, class_name: "User", required: true

  enum :data_type, IssueField::DATA_TYPES, prefix: true, validate: true

  # Validations
  validates :repository_id, presence: true
  validate :issue_field_belongs_to_same_organization_as_issue

  # Custom validation to ensure the field definition belongs to the same organization as the issue
  sig { void }
  def issue_field_belongs_to_same_organization_as_issue
    return unless (issue_field = self.issue_field)
    return unless (issue = self.issue)

    if issue_field.owner_id != issue.repository&.owner_id
      errors.add(:issue_field, :field_and_issue_should_belong_to_same_organization)
    end
  end

  # Abstract method: must be implemented in subclasses
  sig { override.returns(T.untyped) }
  def value
    raise NotImplementedError, "Subclasses must implement the #value method"
  end

  private

  sig { returns(T.untyped) }
  def raw_value
    read_attribute(:value)
  end
end
