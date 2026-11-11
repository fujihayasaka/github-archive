# typed: true
# frozen_string_literal: true

class PlanningTemplate < ApplicationRecord::Domain::IssuesPullRequests
  include GitHub::UTF8
  include GitHub::Validations
  include GitHub::BackgroundDependentDeletes

  TEMPLATE_TYPES = T.let({
    default: 0,
    custom: 1
  }.freeze, T::Hash[Symbol, Integer])

  enum :template_type, TEMPLATE_TYPES, prefix: true, validate: true

  # Associations
  belongs_to :owner, class_name: "User"

  has_many :issue_type_fields_mapping,
    class_name: "PlanningTemplatesTypeFieldsMapping",
    inverse_of: :planning_template
  destroy_dependents_in_background :issue_type_fields_mapping

  has_many :pinned_fields,
    class_name: "PlanningTemplatesPinnedField",
    inverse_of: :planning_template
  destroy_dependents_in_background :pinned_fields

  # Length limits mirror migration constraints
  NAME_LENGTH_LIMIT = 64
  DESCRIPTION_LENGTH_LIMIT = 256

  # Callbacks
  before_validation :strip_whitespace

  # Validations
  validates :owner_id, presence: true
  destroy_in_background_with :owner, polymorphic_class_name: "Organization"

  validates :name,
    presence: true,
    length: { maximum: NAME_LENGTH_LIMIT },
    uniqueness: { scope: :owner, case_sensitive: false },
    unicode: true
  validates :description, length: { maximum: DESCRIPTION_LENGTH_LIMIT }, unicode: true, allow_blank: true
  validates :template_type, presence: true
  validate  :owner_must_be_organization
  validate  :validate_single_default_template, if: :template_type_default?

  private

  def validate_single_default_template
    if PlanningTemplate.where(owner_id: owner_id, template_type: :default).where.not(id: id).exists?
      errors.add(:template_type, "Default template already exists for this organization")
    end
  end

  def strip_whitespace
    self[:name] = self[:name]&.strip
  end

  def owner_must_be_organization
    owner = User.find_by(id: self[:owner_id])
    errors.add(:owner, "Owner must be an organization") if owner && owner.type != "Organization"
  end
end
