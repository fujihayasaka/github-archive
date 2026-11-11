# typed: strict
# frozen_string_literal: true

class IssueFieldValue < ApplicationRecord::Domain::IssuesPullRequests
  include Issues::IIssueFieldValue
  include MemexProjectColumn::IDataSource
  include GitHub::UTF8
  include GitHub::Validations

  self.inheritance_column = :data_type

  sig { params(type_name: String).returns(T.any(T.class_of(IssueFieldTextValue), T.class_of(IssueFieldSingleSelectValue), T.class_of(IssueFieldMultiSelectValue), T.class_of(IssueFieldDateValue), T.class_of(IssueFieldNumberValue))) }
  def self.sti_class_for(type_name)
    case type_name
    when IssueFieldTextValue.sti_name
      IssueFieldTextValue
    when IssueFieldSingleSelectValue.sti_name
      IssueFieldSingleSelectValue
    when IssueFieldMultiSelectValue.sti_name
      IssueFieldMultiSelectValue
    when IssueFieldDateValue.sti_name
      IssueFieldDateValue
    when IssueFieldNumberValue.sti_name
      IssueFieldNumberValue
    else
      raise "Unknown issue field type: #{type_name}"
    end
  end

  # Batch preload issue_field_values for a list of issues using a single query
  # that includes repository_id so MySQL can use the UNIQUE composite index.
  # Assigns results to each issue's association target so subsequent reads
  # don't trigger additional queries.
  sig do
    params(
      issues: T::Array[Issue],
      extra_associations: T.untyped,
    ).void
  end
  def self.preload_for_issues(issues, extra_associations: nil)
    return if issues.empty?

    issue_ids = issues.map(&:id)
    repository_ids = issues.map(&:repository_id).compact.uniq

    relation = where(issue_id: issue_ids)
    relation = relation.where(repository_id: repository_ids) if repository_ids.any?
    values_by_issue_id = relation.to_a.group_by(&:issue_id)

    issues.each do |issue|
      issue.association(:issue_field_values).target = values_by_issue_id.fetch(issue.id, []) # rubocop:disable GitHub/DontCallAssociationTargetEquals
    end

    if extra_associations
      all_values = values_by_issue_id.values.flatten
      ::ActiveRecord::Associations::Preloader.new(records: all_values, associations: extra_associations).call if all_values.any?
    end
  end

  # Associations
  belongs_to :issue_field, required: true
  belongs_to :issue, required: true, touch: true
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
  # Returns a value suitable for indexing in ElasticSearch flattened fields (string or array of strings)
  sig { returns(T.nilable(T.any(String, T::Array[String]))) }
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

    option_ids = if self.is_a?(IssueFieldMultiSelectValue)
      raw = read_attribute(:value)
      raw.is_a?(Array) ? raw : nil
    end
    prev_option_ids = if self.is_a?(IssueFieldMultiSelectValue)
      if created
        nil
      elsif destroyed
        option_ids
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
      issue_field_option_ids: option_ids,
      destroyed: destroyed,
      created: created,
      issue_field_prev_option_id: prev_option_id,
      issue_field_prev_option_ids: prev_option_ids,
      issue_field_prev_value: prev_value,
    }

    issue.synchronize_search_index
    issue.touch_memex_project_items
  end
end
