# typed: strict
# frozen_string_literal: true

# `MemexProjectColumn::Field::IssueField::Base` is an abstract class that represents an issue field in a project.
#
# The abstract class provides a common interface for all issue fields, such as text fields, date fields, etc. Given
# issue fields need to be indexable before the field itself exists in the project, this class provides
# the necessary functionality to ensure that issue fields can be properly indexed and queried once they are created.
#
# This class should not be instantiated directly. Instead, subclasses should be created for each specific issue field
# type. See `MemexProjectColumn::Field::IssueField::Text` for an example of a concrete implementation.
class MemexProjectColumn::Field::IssueField::Base < MemexProjectColumn::Field::Base
  include Interface::SpecialTypeSerializable

  abstract!

  sig { override.returns(T::Array[MemexProjectItem::ContentType]) }
  def self.supported_content_types = [MemexProjectItem::ContentType::Issue]

  sig { returns(Symbol) }
  def self.value_name
    "issue_field_#{data_type}_value".to_sym
  end

  # Field values representing an IssueField value need to be serialized with the `issue_field_id` property so they
  # can be queried before the `MemexProjectColumn` may exist.
  sig { override.returns(Elastomer::Interfaces::Document::MemexProjectItem::FieldValues::FieldIdProperty) }
  def elasticsearch_field_id
    Elastomer::Interfaces::Document::MemexProjectItem::FieldValues::FieldIdProperty::IssueFieldId.new(issue_field_id)
  end

  sig do
    override
      .overridable
      .params(item: MemexProjectItem)
      .returns(T.nilable(Elastomer::Interfaces::Document::MemexProjectItem::Value))
  end
  def elasticsearch_document(item)
    content_type = MemexProjectItem::ContentType.deserialize(item.content_type)

    case content_type
    when MemexProjectItem::ContentType::Issue
      return unless issue_field?

      issue = T.cast(item.content, Issue) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      issue_field_value = issue.issue_field_values.find do |field_value|
        field_value.issue_field_id == issue_field_id
      end
      return unless issue_field_value

      issue_field_value.value
    when MemexProjectItem::ContentType::DraftIssue,
      MemexProjectItem::ContentType::PullRequest,
      MemexProjectItem::ContentType::AgentTask

      nil
    else
      T.absurd(content_type)
    end
  end

  # GraphQL expects a string and not nulls
  sig { override.params(group_by_value: T.nilable(String)).returns(T.nilable(String)) }
  def graphql_value(group_by_value)
    # Calling super helps cleanse potential _noValue values
    super(group_by_value).to_s
  end

  sig(:final) do
    override
      .params(items: T::Array[MemexProjectItem], fields: T::Array[MemexProjectColumn::Field::Base])
      .returns(T.nilable(T::Hash[Integer, T.untyped]))
  end
  private def preload_web_api_response_data(items:, fields:)
    return if preloaded_web_api_response_data?

    supported_items = items.select(&:issue?)

    # Fetch data across all issue fields (not just the one against which this method was invoked) at once!
    issue_fields = fields.select(&:issue_field?)
    repository_ids = supported_items.map(&:repository_id).compact.uniq
    relation = IssueFieldValue
      .includes({ issue_field: :options })
      .where(issue_id: supported_items.map(&:issue_id), issue_field_id: issue_fields.map(&:issue_field_id))
    relation = relation.where(repository_id: repository_ids) if repository_ids.any?
    values_by_issue_id = relation.group_by(&:issue_id)

    # Proactively cache the preloaded data in the `preloaded_web_api_response_data` instance variable of each
    # individual field.
    #
    # This is different from other implementations of `preload_web_api_response_data` which return a hash and allow
    # the `Serializable::WebApi` interface to handle the caching. Doing it this way allows us to cache data for all
    # issue fields at once so that we only ever pay this cost once.
    issue_fields.each do |issue_field|
      issue_field.preloaded_web_api_response_data = items.each_with_object({}) do |item, result|
        next unless item.issue?
        result[item.id] = values_by_issue_id
          .fetch(item.issue_id, [])
          .find { |v| v.issue_field_id == issue_field.issue_field_id && v.memex_column_value_present? }
      end
    end

    # Return `nil` so that the `Serializable::WebApi` interface doesn't attempt to handle caching for us.
    nil
  end

  sig do
    override.
      params(
        item: MemexProjectItem,
        prefilled_associations: T.nilable(MemexProjectItem::PrefilledAssociations),
        redacted_issue_ids: T::Array[Integer],
      ).
      returns(T.nilable(MemexProjectColumn::IDataSource))
  end
  def serializable(item, prefilled_associations: nil, redacted_issue_ids: [])
    content_type = MemexProjectItem::ContentType.deserialize(item.content_type)

    case content_type
    when MemexProjectItem::ContentType::Issue
      return unless issue_field?

      if prefilled_associations
        return unless (issue_field_value = prefilled_associations.issue_field_value(item, issue_field_id))
        return if redacted_issue_ids.include?(issue_field_value.issue_id)

        issue_field_value
      elsif preloaded_web_api_response_data?
        return if redacted_issue_ids.include?(item.content_id)
        preloaded_web_api_response_data[item.id]
      else
        issue = T.cast(item.content, Issue) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        return if redacted_issue_ids.include?(issue.id)

        issue_field_value = issue.issue_field_values.find { |fv| fv.issue_field_id == issue_field_id }
        return unless issue_field_value&.memex_column_value_present?
        issue_field_value
      end
    when MemexProjectItem::ContentType::PullRequest,
      MemexProjectItem::ContentType::DraftIssue,
      MemexProjectItem::ContentType::AgentTask
      nil
    else
      T.absurd(content_type)
    end
  end

  sig { override.returns(T::Hash[T.untyped, T.untyped]) }
  def existence_fragment
    {
      nested: {
        path: "field_values",
        query: elasticsearch_field_value_term_filter,
      }
    }
  end

  sig do
    override.
      params(
        item: MemexProjectItem,
        new_value: T.untyped,
        actor: User,
        suppress_hydro_events: T::Boolean,
      ).
      returns(MemexProjectColumn::Interface::Writeable::PartialResult)
  end
  private def update_mysql_field_value(item:, new_value:, actor:, suppress_hydro_events:)
    retry_on_find_or_create_error do
      unless item.issue?
        return Interface::Writeable::PartialResult.failure("Only issues are supported")
      end

      issue = item.issue_for_content
      issue_field = self.issue_field

      if issue.nil?
        return MemexProjectColumn::Interface::Writeable::PartialResult.failure(
          "Issue does not exist"
        )
      end

      unless issue.can_set_issue_field_value?(actor:)
        return MemexProjectColumn::Interface::Writeable::PartialResult.failure(
          "User does not have permission to set the issue field value"
        )
      end

      if new_value.present?
        change_mysql_value(issue:, issue_field:, new_value:, actor:, suppress_hydro_events:)
      else
        delete_mysql_value(issue:, issue_field:, suppress_hydro_events:)
      end
    end
  end

  sig do
    params(
      issue: Issue,
      issue_field: T.nilable(IssueField),
      suppress_hydro_events: T::Boolean,
    )
    .returns(MemexProjectColumn::Interface::Writeable::PartialResult)
  end
  private def delete_mysql_value(issue:, issue_field:, suppress_hydro_events:)
    if issue_field
      issue.issue_field_values.where(issue_field:, repository_id: issue.repository_id).destroy_all
      MemexProjectColumn::Interface::Writeable::PartialResult.success
    else
      MemexProjectColumn::Interface::Writeable::PartialResult.success
    end
  end

  sig do
    params(issue: Issue, issue_field: T.nilable(IssueField), new_value: T.untyped, actor: User, suppress_hydro_events: T::Boolean)
    .returns(MemexProjectColumn::Interface::Writeable::PartialResult)
  end
  private def change_mysql_value(issue:, issue_field:, new_value:, actor:, suppress_hydro_events:)
    if issue_field.nil?
      return MemexProjectColumn::Interface::Writeable::PartialResult.failure(
        "Issue field does not exist"
      )
    end
    issue_field_value = issue.issue_field_values.find_or_initialize_by(issue_field:) do |new_field_value|
      new_field_value.repository = issue.repository
      new_field_value.data_type = issue_field.data_type
    end

    if issue_field_value.update(actor:, value: new_value)
      MemexProjectColumn::Interface::Writeable::PartialResult.success
    else
      MemexProjectColumn::Interface::Writeable::PartialResult.failure(
        "Must be a valid value for #{data_type} column",
        attribute: :column_value
      )
    end
  end
end
