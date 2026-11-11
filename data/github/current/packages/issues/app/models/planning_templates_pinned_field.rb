# typed: true
# frozen_string_literal: true

class PlanningTemplatesPinnedField < ApplicationRecord::Domain::IssuesPullRequests
  include GitHub::Validations
  include GitHub::BackgroundDependentDeletes

  MAX_PINNED_FIELDS_PER_TEMPLATE = 10

  belongs_to :planning_template, class_name: "PlanningTemplate", inverse_of: :pinned_fields
  destroy_in_background_with :planning_template, sharding_key: :owner_id, sharding_value_key: :owner_id

  belongs_to :owner, class_name: "User"
  belongs_to :issue_field, class_name: "IssueField", inverse_of: :planning_templates_pinned_fields

  before_validation :set_owner_id_from_template

  validates :planning_template_id, :owner_id, :issue_field_id, presence: true
  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  validates :issue_field_id, uniqueness: { scope: [:owner_id, :planning_template_id] }
  validates :position, uniqueness: { scope: [:owner_id, :planning_template_id] }

  validate :owner_must_be_organization
  validate :owner_id_matches_planning_template_owner_id
  validate :issue_field_belongs_to_owner
  validate :validate_pinned_fields_limit, on: :create

  private

  def validate_pinned_fields_limit
    return unless owner_id && planning_template_id

    if self.class.where(owner_id: owner_id, planning_template_id: planning_template_id).offset(MAX_PINNED_FIELDS_PER_TEMPLATE - 1).exists?
      errors.add(:base, "Maximum of #{MAX_PINNED_FIELDS_PER_TEMPLATE} pinned fields allowed per template")
    end
  end

  def set_owner_id_from_template
    return if owner_id.present?

    self.owner_id = planning_template&.owner_id if planning_template
  end

  def owner_id_matches_planning_template_owner_id
    return unless owner_id
    return unless (planning_template = self.planning_template)

    if owner_id != planning_template.owner_id
      errors.add(:owner_id, "must match planning template owner")
    end
  end

  def issue_field_belongs_to_owner
    return unless owner_id
    return unless (issue_field = self.issue_field)

    if issue_field.owner_id != owner_id
      errors.add(:issue_field, "must belong to the same organization as the template")
    end
  end

  def owner_must_be_organization
    owner = User.find_by(id: self[:owner_id])
    errors.add(:owner, "Owner must be an organization") if owner && owner.type != "Organization"
  end
end
