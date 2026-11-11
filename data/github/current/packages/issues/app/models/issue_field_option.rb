# typed: strict
# frozen_string_literal: true

class IssueFieldOption < ApplicationRecord::Domain::IssuesPullRequests
  include Issues::IIssueFieldOption
  include GitHub::UTF8
  include GitHub::Validations
  include MemexProjectColumn::IDataSource
  include GitHub::Memoizer

  # Constants for validation limits
  MAX_NAME_LENGTH = T.let(50, Integer)
  MAX_DESCRIPTION_LENGTH = T.let(100, Integer)
  MAX_OPTIONS_PER_FIELD = T.let(100, Integer)

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
  validates :name, presence: true, uniqueness: { scope: :issue_field_id, case_sensitive: false }, length: { maximum: MAX_NAME_LENGTH }
  validates :description, length: { maximum: MAX_DESCRIPTION_LENGTH }, allow_blank: true
  validates :color, presence: true
  validate :issue_field_must_be_select_type
  validate :name_cannot_contain_comma_for_multi_select
  validate :check_options_limit

  # Set owner from issue_field before validation if not already set
  before_validation :set_owner_from_issue_field
  before_validation :trim_name

  #normalize color to ensure it is a valid symbol
  before_validation :normalize_color

  # After an option is destroyed, we queue a background job to find
  # and clear all issue field values that are set to this option.
  after_destroy_commit :clear_associated_issue_field_values # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  after_create_commit :instrument_create # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_update_commit :instrument_update # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_destroy_commit :instrument_destroy # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  sig { params(options: T::Array[IssueFieldOption]).returns(T::Array[IssueFieldOption]) }
  def self.sorted_options(options)
    options.sort_by do |o|
      [o.priority || 0, o.id]
    end
  end

  sig { returns(T.nilable(Integer)) }
  def color_id
    normalized_symbol = color.to_sym
    COLORS[normalized_symbol]
  end

  sig { returns(String) }
  def platform_type_name
    "IssueFieldSingleSelectOption"
  end

  sig { returns(MemexProjectColumn::Settings::OptionEntry) }
  def memex_project_column_entry
    MemexProjectColumn::Settings::OptionEntry.new(
      id: id.to_s,
      name:,
      color: color.upcase,
      description:,
    )
  end

  sig { override.returns(MemexProjectColumnValue::OptionEntry) }
  memoize def memex_project_column_value
    memex_project_column_entry.memex_project_column_value
  end

  private

  sig { void }
  def normalize_color
    return if color.blank?

    normalized_symbol = color.downcase.to_sym

    if COLORS.key?(normalized_symbol)
      self.color = normalized_symbol
    end
  end

  sig { void }
  def issue_field_must_be_select_type
    return unless issue_field

    unless T.must(issue_field).data_type_single_select? || T.must(issue_field).data_type_multi_select?
      errors.add(:issue_field, :invalid_data_type, data_type: "single_select or multi_select")
    end
  end

  sig { void }
  def name_cannot_contain_comma_for_multi_select
    return unless issue_field && T.must(issue_field).data_type_multi_select?
    return unless name&.include?(",")

    errors.add(:name, :cannot_contain_comma)
  end

  sig { void }
  def check_options_limit
    return unless new_record? # Only check on create
    return unless issue_field

    existing_options_count = T.must(issue_field).options.count
    if existing_options_count >= MAX_OPTIONS_PER_FIELD
      errors.add(:base, "Cannot add more options. Maximum of #{MAX_OPTIONS_PER_FIELD} options allowed per field.")
    end
  end

  sig { void }
  def set_owner_from_issue_field
    return if owner.present? || issue_field.blank?

    self.owner = T.must(issue_field).owner
  end

  sig { void }
  def trim_name
    self.name = name&.strip
  end

  sig { void }
  def clear_associated_issue_field_values
    ClearIssueFieldValuesJob.perform_later(issue_field_id: issue_field_id, issue_field_option_id: id)
  end

  sig { returns(User) }
  def modifying_user
    User.find_by(id: GitHub.context[:actor_id]) || User.ghost
  end

  sig { void }
  def instrument_create
    GlobalInstrumenter.instrument "issue_field_option.create", {
      actor: modifying_user,
      issue_field: issue_field,
      issue_field_option: self,
    }
  end

  sig { void }
  def instrument_update
    GlobalInstrumenter.instrument "issue_field_option.update", {
      actor: modifying_user,
      issue_field: issue_field,
      issue_field_option: self,
    }
  end

  sig { void }
  def instrument_destroy
    # When an IssueFieldOption is destroyed via the parent IssueField's
    # `destroy_dependents_in_background :options` cascade, the parent
    # IssueField row has already been deleted by the time this callback
    # fires. In that case `issue_field` resolves to nil and downstream
    # consumers (e.g. memex live updates) cannot route the event because
    # the resulting Hydro message has no `issue_field` payload. The
    # parallel `IssueFieldDestroy` event already drives the cascade
    # cleanup downstream, so skipping here is safe.
    if issue_field.nil? &&
        FeatureFlag.vexi.enabled?(:issue_field_option_destroy_cascade_resilience, default: false)
      return
    end

    GlobalInstrumenter.instrument "issue_field_option.destroy", {
      actor: modifying_user,
      issue_field: issue_field,
      issue_field_option: self,
    }
  end
end
