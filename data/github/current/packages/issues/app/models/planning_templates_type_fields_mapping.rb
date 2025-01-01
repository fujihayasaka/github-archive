# typed: true
# frozen_string_literal: true

class PlanningTemplatesTypeFieldsMapping < ApplicationRecord::Domain::IssuesPullRequests
  include GitHub::Validations
  include GitHub::BackgroundDependentDeletes

  # Associations
  belongs_to :planning_template, class_name: "PlanningTemplate", inverse_of: :issue_type_fields_mapping
  destroy_in_background_with :planning_template

  belongs_to :owner, class_name: "User"

  belongs_to :issue_type, class_name: "IssueType"
  belongs_to :issue_field, class_name: "IssueField"

  # Validations
  validates :planning_template_id, :owner_id, :issue_type_id, :issue_field_id, presence: true
  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :issue_field_id, uniqueness: { scope: [:planning_template_id, :issue_type_id] }
  validates :position, uniqueness: { scope: [:planning_template_id, :issue_type_id] }

  validate  :owner_must_be_organization

  private

  def owner_must_be_organization
    valid_owner = planning_template&.owner_id || self[:owner_id]
    owner = User.find_by(id: valid_owner)
    errors.add(:owner, "Owner must be an organization") if owner && owner.type != "Organization"
  end
end
