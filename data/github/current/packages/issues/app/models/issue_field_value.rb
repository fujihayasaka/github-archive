# typed: strict
# frozen_string_literal: true

class IssueFieldValue < ApplicationRecord::Domain::IssuesPullRequests
  include Issues::IIssueFieldValue
  include MemexProjectColumn::IDataSource
  include GitHub::UTF8
  include GitHub::Validations

  self.inheritance_column = :data_type

  sig { params(type_name: String).returns(T.any(T.class_of(IssueFieldTextValue), T.class_of(IssueFieldSingleSelectValue), T.class_of(IssueFieldDateValue), T.class_of(IssueFieldNumberValue))) }
  def self.sti_class_for(type_name)
    case type_name
    when IssueFieldTextValue.sti_name
      IssueFieldTextValue
    when IssueFieldSingleSelectValue.sti_name
      IssueFieldSingleSelectValue
    when IssueFieldDateValue.sti_name
      IssueFieldDateValue
    when IssueFieldNumberValue.sti_name
      IssueFieldNumberValue
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
  validates :issue_field_id, uniqueness: { scope: [:repository_id, :issue_id] }
  validate :issue_field_belongs_to_same_organization_as_issue

  # Callbacks
  after_commit :trigger_issue_field_value_change_events # rubocop:todo GitHub/AvoidActiveRecordCallbacks

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

  # Abstract method: must be implemented in subclasses to provide ElasticSearch serialization
  # Returns a string value suitable for indexing in ElasticSearch flattened fields
  sig { returns(T.nilable(String)) }
  def elasticsearch_value
    raise NotImplementedError, "Subclasses must implement the #elasticsearch_value method"
  end

  sig { returns(T::Boolean) }
  def memex_column_value_present?
    raise NotImplementedError, "Subclasses must implement the #memex_column_value_present? method"
  end

  private

  sig { returns(T.untyped) }
  def raw_value
    read_attribute(:value)
  end

  sig { void }
  def validate_raw_value_presence
    if raw_value.blank?
      errors.add(:value, :blank)
    end
  end

  sig { void }
  def trigger_issue_field_value_change_events
    return unless (issue = self.issue)
    return unless (issue_field = self.issue_field)
    return unless (repository = issue.repository)

    Platform::Schema.subscriptions.trigger(:issue_updated, { id: issue.global_relay_id }, object: { issue_fields_updated: true })

    destroyed = previous_changes.empty? && destroyed?
    created = previous_changes.any? && saved_change_to_id?

    option_id = self.is_a?(IssueFieldSingleSelectValue) ? self.option&.id : nil
    prev_option_id = if self.is_a?(IssueFieldSingleSelectValue)
      if created
        nil
      elsif destroyed
        option_id
      else
        previous_changes.dig("value", 0)
      end
    end

    # Capture previous value for all field types
    prev_value = unless created || destroyed
      previous_changes.dig("value", 0)
    end

    # Use context actor_id or fall back to the stored actor_id
    actor_id = GitHub.context[:actor_id] || self.actor_id

    GlobalInstrumenter.instrument "issue.issue_field_value.changed", {
      actor_id: actor_id,
      repository: repository,
      issue: issue,
      issue_field: issue_field,
      issue_field_value: self,
      issue_field_option_id: option_id,
      destroyed: destroyed,
      created: created,
      issue_field_prev_option_id: prev_option_id,
      issue_field_prev_value: prev_value,
    }
  end
end
