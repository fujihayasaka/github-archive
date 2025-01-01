# typed: strict
# frozen_string_literal: true

class IssueField < ApplicationRecord::Domain::IssuesPullRequests
  include Issues::IIssueField
  include GitHub::UTF8
  include GitHub::Validations
  include GitHub::BackgroundDependentDeletes

  self.inheritance_column = :data_type

  sig { params(type_name: T.any(String, Symbol)).returns(T.any(T.class_of(IssueField), T.class_of(IssueFieldText), T.class_of(IssueFieldSingleSelect))) }
  def self.sti_class_for(type_name)
    case type_name
    when IssueFieldText.sti_name
      IssueFieldText
    when IssueFieldSingleSelect.sti_name
      IssueFieldSingleSelect
    else
      IssueField
    end
  end

  ORGANIZATION_ISSUE_FIELDS_LIMIT = 50

  # Associations
  belongs_to :owner, class_name: "User"
  destroy_in_background_with :owner, polymorphic_class_name: "Organization"

  belongs_to :actor, class_name: "User"
  has_many :values, class_name: "IssueFieldValue", inverse_of: :issue_field
  has_many :options, class_name: "IssueFieldOption", inverse_of: :issue_field

  DATA_TYPES = T.let({
    text: 0,
    single_select: 1
  }.freeze, T::Hash[Symbol, Integer])

  enum :data_type, DATA_TYPES, prefix: true, validate: true

  before_validation :generate_name_slug, if: :should_generate_name_slug?

  # Validations
  validates :owner_id, presence: true
  validates :name, presence: true, uniqueness: { scope: :owner, case_sensitive: false }
  validates :name_slug, presence: true, uniqueness: { scope: :owner, case_sensitive: false }
  validate  :name_is_not_reserved
  validate  :owner_must_be_organization
  validates :data_type, presence: true
  validates :actor_id, presence: true

  RESERVED_NAMES = %w[
    title
    labels
    types
    assignees
    repository
  ].freeze

  private

  sig { void }
  def name_is_not_reserved
    return unless name_changed?

    if RESERVED_NAMES.any? { |r| r.casecmp?(name) }
      errors.add(:name, "cannot have a reserved value")
    end
  end

  sig { void }
  def owner_must_be_organization
    if owner.present? && owner&.type != "Organization"
      errors.add(:owner, "Owner must be an organization")
    end
  end

  sig { void }
  def generate_name_slug
    self.name_slug = name&.parameterize
  end

  sig { returns(T::Boolean) }
  def should_generate_name_slug?
    will_save_change_to_name? || name_slug.blank?
  end
end
