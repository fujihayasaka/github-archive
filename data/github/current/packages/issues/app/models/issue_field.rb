# typed: strict
# frozen_string_literal: true

class IssueField < ApplicationRecord::Domain::IssuesPullRequests
  include Issues::IIssueField
  include GitHub::UTF8
  include GitHub::Validations
  include GitHub::BackgroundDependentDeletes
  include GitHub::Memoizer

  self.inheritance_column = :data_type

  sig { params(type_name: T.any(String, Symbol)).returns(T.any(T.class_of(IssueField), T.class_of(IssueFieldText), T.class_of(IssueFieldSingleSelect))) }
  def self.sti_class_for(type_name)
    case type_name
    when IssueFieldText.sti_name
      IssueFieldText
    when IssueFieldSingleSelect.sti_name
      IssueFieldSingleSelect
    when IssueFieldDate.sti_name
      IssueFieldDate
    when IssueFieldNumber.sti_name
      IssueFieldNumber
    else
      IssueField
    end
  end

  # Constants for validation limits
  MAX_NAME_LENGTH = T.let(25, Integer)
  MAX_DESCRIPTION_LENGTH = T.let(100, Integer)
  ORGANIZATION_ISSUE_FIELDS_LIMIT = T.let(25, Integer)

  # Associations
  belongs_to :owner, class_name: "User"
  destroy_in_background_with :owner, polymorphic_class_name: "Organization"

  belongs_to :actor, class_name: "User"
  has_many :values, class_name: "IssueFieldValue", inverse_of: :issue_field
  has_many :options, class_name: "IssueFieldOption", inverse_of: :issue_field

  DATA_TYPES = T.let({
    text: 0,
    single_select: 1,
    date: 2,
    number: 3
  }.freeze, T::Hash[Symbol, Integer])

  enum :data_type, DATA_TYPES, prefix: true, validate: true

  before_validation :generate_name_slug, if: :should_generate_name_slug?
  before_validation :trim_name

  # Validations
  validates :owner_id, presence: true
  validates :name, presence: true, uniqueness: { scope: :owner, case_sensitive: false }, length: { in: 1..MAX_NAME_LENGTH }
  validates :description, length: { maximum: MAX_DESCRIPTION_LENGTH }, allow_blank: true
  validates :name_slug, presence: true, uniqueness: { scope: :owner, case_sensitive: false }
  validate  :name_is_not_reserved
  validate  :owner_must_be_organization
  validate  :check_organization_field_limit
  validates :data_type, presence: true
  validates :actor_id, presence: true
  after_commit :instrument_create, on: :create # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_update, on: :update # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_destroy, on: :destroy # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  RESERVED_NAMES = [
    "Assignee",
    "Assignees",
    "author",
    "blocked by",
    "created",
    "development",
    "involves",
    "is",
    "is blocking",
    "Label",
    "Labels",
    "linked",
    "Linked issue",
    "Linked issues",
    "Linked pull request",
    "Linked pull requests",
    "Milestone",
    "no",
    "notifications",
    "org",
    "parent-issue",
    "Parent issue",
    "participants",
    "project",
    "projects",
    "reactions",
    "reason",
    "relationships",
    "Repo",
    "Repository",
    "review",
    "reviewed-by",
    "Reviewer",
    "Reviewers",
    "state",
    "Status",
    "sub-issue",
    "Sub-issues progress",
    "team-review-requested",
    "Title",
    "Tracked by",
    "Tracks",
    "type",
    "updated",
    "user"
  ].freeze

  # Type alias for any issue field type
  IssueFieldType = T.type_alias { T.any(Issues::IIssueFieldText, Issues::IIssueFieldSingleSelect, Issues::IIssueFieldDate, Issues::IIssueFieldNumber) }

  # Type alias for issue field attributes
  IssueFieldAttributesType = T.type_alias do
    T.any(
      Issues::IssueFieldTextValueAttributes,
      Issues::IssueFieldSingleSelectValueAttributes,
      Issues::IssueFieldDateValueAttributes,
      Issues::IssueFieldNumberValueAttributes
    )
  end

  sig { override.returns(T::Hash[Symbol, T.untyped]) }
  def to_json_react
    {
      id: id,
      name: name,
      type: data_type,
      description: description,
    }
  end

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
  def check_organization_field_limit
    return unless new_record? # Only check on create
    return unless owner

    existing_fields_count = IssueField.where(owner: owner).count
    if existing_fields_count >= ORGANIZATION_ISSUE_FIELDS_LIMIT
      errors.add(:base, "Cannot create more fields. Maximum of #{ORGANIZATION_ISSUE_FIELDS_LIMIT} fields allowed per organization.")
    end
  end

  sig { void }
  def trim_name
    self.name = name&.strip
  end

  sig { void }
  def generate_name_slug
    self.name_slug = name&.parameterize
  end

  sig { returns(T::Boolean) }
  def should_generate_name_slug?
    will_save_change_to_name? || name_slug.blank?
  end

  sig { returns(User) }
  memoize def modifying_user
    User.find_by(id: GitHub.context[:actor_id]) || User.ghost
  end

  sig { void }
  def instrument_create
    GlobalInstrumenter.instrument "issue_field.create", {
      actor: modifying_user,
      issue_field: self,
    }
  end

  sig { void }
  def instrument_update
    message = {
      actor: Hydro::EntitySerializer.user(modifying_user),
      issue_field: Hydro::EntitySerializer.issue_field(self)
    }

    # Use aqueduct_fallback_hydro_publisher for better publishing guarantees.
    # Required to update any associated project columns.
    GitHub.aqueduct_fallback_hydro_publisher.publish(
      message,
      schema: "github.v1.IssueFieldUpdate"
    )
  end

  sig { void }
  def instrument_destroy
    message = {
      actor: Hydro::EntitySerializer.user(modifying_user),
      issue_field: Hydro::EntitySerializer.issue_field(self)
    }

    # Use aqueduct_fallback_hydro_publisher for better publishing guarantees
    # Required to update any associated project columns.
    GitHub.aqueduct_fallback_hydro_publisher.publish(
      message,
      schema: "github.v1.IssueFieldDestroy"
    )
  end
end
