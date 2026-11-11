# typed: strict
# frozen_string_literal: true

class IssueField < ApplicationRecord::Domain::IssuesPullRequests
  include Issues::IIssueField
  include GitHub::UTF8
  include GitHub::Validations
  include GitHub::BackgroundDependentDeletes
  include GitHub::Memoizer

  self.inheritance_column = :data_type

  sig do
    params(type_name: T.any(String, Symbol)).returns(
      T.any(
        T.class_of(IssueField),
        T.class_of(IssueFieldText),
        T.class_of(IssueFieldSingleSelect),
        T.class_of(IssueFieldMultiSelect),
        T.class_of(IssueFieldDate),
        T.class_of(IssueFieldNumber),
      ),
    )
  end
  def self.sti_class_for(type_name)
    case type_name
    when IssueFieldText.sti_name
      IssueFieldText
    when IssueFieldSingleSelect.sti_name
      IssueFieldSingleSelect
    when IssueFieldMultiSelect.sti_name
      IssueFieldMultiSelect
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

  has_many :planning_templates_pinned_fields,
    ->(field) { where(owner_id: field.owner_id) },
    class_name: "PlanningTemplatesPinnedField",
    inverse_of: :issue_field
  has_many :planning_templates_type_fields_mappings,
    ->(field) { where(owner_id: field.owner_id) },
    class_name: "PlanningTemplatesTypeFieldsMapping",
    inverse_of: :issue_field

  DATA_TYPES = T.let({
    text: 0,
    single_select: 1,
    date: 2,
    number: 3,
    multi_select: 4
  }.freeze, T::Hash[Symbol, Integer])

  VISIBILITIES = T.let({
    org_only: 0,
    all: 1
  }.freeze, T::Hash[Symbol, Integer])

  enum :data_type, DATA_TYPES, prefix: true, validate: true
  enum :visibility, VISIBILITIES, prefix: true, validate: true

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
  validates :visibility, presence: true
  validates :actor_id, presence: true
  after_commit :instrument_create, on: :create # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_update, on: :update # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_destroy, on: :destroy # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  RESERVED_NAMES = [
    "Assignee",
    "Assignees",
    "author",
    "blocked by",
    "closed",
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
  IssueFieldType = T.type_alias { T.any(Issues::IIssueFieldText, Issues::IIssueFieldSingleSelect, Issues::IIssueFieldMultiSelect, Issues::IIssueFieldDate, Issues::IIssueFieldNumber) }

  # Type alias for issue field attributes
  IssueFieldAttributesType = T.type_alias do
    T.any(
      Issues::IssueFieldTextValueAttributes,
      Issues::IssueFieldSingleSelectValueAttributes,
      Issues::IssueFieldMultiSelectValueAttributes,
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

  sig { params(data_type: T.any(String, Symbol)).returns(T.nilable(Integer)) }
  def self.data_type_to_int(data_type)
    case data_type
    when "TEXT", :TEXT
      DATA_TYPES[:text]
    when "SINGLE_SELECT", :SINGLE_SELECT
      DATA_TYPES[:single_select]
    when "DATE", :DATE
      DATA_TYPES[:date]
    when "NUMBER", :NUMBER
      DATA_TYPES[:number]
    when "MULTI_SELECT", :MULTI_SELECT
      DATA_TYPES[:multi_select]
    else
      raise ArgumentError, "Unknown data type: #{data_type}"
    end
  end

  sig { override.params(viewer: T.nilable(User), repository_id: T.nilable(Integer)).returns(T::Boolean) }
  def viewable_by?(viewer:, repository_id: nil)
    case visibility.to_sym
    when :org_only
      return false unless owner.present? && viewer.present?
      if viewer.can_have_granular_permissions?
        return true if T.unsafe(owner).resources.issue_fields.readable_by?(viewer)
        # Fall back to issues:read for installations (e.g. GITHUB_TOKEN) without issue_fields:read
        return installation_has_issues_access_on_repo?(viewer, repository_id)
      end
      return true if T.unsafe(owner).member?(viewer)
      # Only allow outside collaborators if scoped to a specific repository they collaborate on
      repository_id.present? && T.unsafe(owner).user_collaborates_on_any_repositories?(viewer.id, [repository_id])
    when :all
      true
    else
      false
    end
  end

  # Raised by `build_value_attributes` when a user-supplied raw value can't be
  # coerced into the typed attributes struct for this field's data_type (e.g.
  # number field given a string, or single_select given an option name that
  # doesn't exist). Callers translate this into their own user-facing error
  # (REST 422, GraphQL Errors::Unprocessable, etc.).
  class InvalidValueError < StandardError; end

  # Builds the typed `Issues::IssueField*ValueAttributes` struct for this field
  # from a user-supplied raw value, performing the coarse type/conversion
  # checks needed before the value is handed to
  # `IssueFields::Builder.build_issue_field_values` (which then enforces the
  # domain-level rules — data_type matching, option existence, ISO 8601 date
  # parsing, etc.). Centralizing this conversion ensures the REST API and the
  # GraphQL apply-suggestion mutation can't drift apart.
  #
  # Conversions:
  #   * single_select: takes the option name and resolves it to an option id.
  #   * text/number/date: pass through after a coarse type check; deeper format
  #     validation happens inside the Builder / IssueFieldValue validations.
  #
  # Raises InvalidValueError when the raw value can't be coerced.
  sig { params(raw_value: T.untyped).returns(IssueFieldAttributesType) }
  def build_value_attributes(raw_value)
    case data_type
    when "text"
      unless raw_value.is_a?(String)
        raise InvalidValueError, "Issue field value for field with id #{id} must be a string"
      end
      Issues::IssueFieldTextValueAttributes.new(
        field_id: id,
        text_value: raw_value,
      )
    when "single_select"
      unless raw_value.is_a?(String)
        raise InvalidValueError, "Issue field value for field with id #{id} must be a string option name"
      end
      option = options.find_by(name: raw_value, owner_id: owner_id)
      if option.nil?
        raise InvalidValueError, "Issue field option with name #{raw_value} does not exist"
      end
      Issues::IssueFieldSingleSelectValueAttributes.new(
        field_id: id,
        option_id: option.id,
      )
    when "multi_select"
      unless raw_value.is_a?(Array)
        raise InvalidValueError, "Issue field value for field with id #{id} must be an array of option names"
      end

      if raw_value.empty?
        raise InvalidValueError, "Issue field value for field with id #{id} must contain at least one option"
      end

      option_names = raw_value.map(&:to_s)
      options_by_name = options.where(name: option_names, owner_id: owner_id).index_by(&:name)
      missing_name = option_names.find { |name| !options_by_name.key?(name) }
      raise InvalidValueError, "Issue field option with name #{missing_name} does not exist" if missing_name

      option_ids = option_names.map { |name| options_by_name.fetch(name).id }
      Issues::IssueFieldMultiSelectValueAttributes.new(
        field_id: id,
        option_ids: option_ids,
      )
    when "number"
      unless raw_value.is_a?(Numeric)
        raise InvalidValueError, "Issue field value for field with id #{id} must be a number"
      end
      Issues::IssueFieldNumberValueAttributes.new(
        field_id: id,
        number_value: raw_value,
      )
    when "date"
      unless raw_value.is_a?(String) && raw_value.present?
        raise InvalidValueError, "Issue field value for field with id #{id} must be a date string"
      end
      Issues::IssueFieldDateValueAttributes.new(
        field_id: id,
        date_value: raw_value,
      )
    else
      raise InvalidValueError, "Unsupported issue field type for field with id #{id}"
    end
  end

  private

  sig { params(viewer: User, repository_id: T.nilable(Integer)).returns(T::Boolean) }
  def installation_has_issues_access_on_repo?(viewer, repository_id)
    return false unless FeatureFlag.vexi.enabled?(:issue_fields_visible_via_issues_permission, self.owner, default: false)
    return false unless repository_id.present?

    delegate = T.unsafe(viewer).try(:ability_delegate)
    return false unless delegate.respond_to?(:target_id) && delegate.respond_to?(:repository_ids)
    return false unless delegate.target_id == T.must(owner).id

    delegate.repository_ids(
      resource: "issues",
      repository_ids: [repository_id],
      organization: T.must(owner)
    ).include?(repository_id)
  end

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
