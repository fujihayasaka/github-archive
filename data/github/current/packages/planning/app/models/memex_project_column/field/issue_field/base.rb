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
      MemexProjectItem::ContentType::PullRequest

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
      else
        issue = T.cast(item.content, Issue) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        return if redacted_issue_ids.include?(issue.id)

        issue.issue_field_values.find { |fv| fv.issue_field_id == issue_field_id }
      end
    when MemexProjectItem::ContentType::PullRequest,
      MemexProjectItem::ContentType::DraftIssue
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
      if new_value.present?
        change_mysql_value(item:, new_value:, actor:, suppress_hydro_events:)
      else
        delete_mysql_value(item:, suppress_hydro_events:)
      end
    end
  end

  sig do
    params(
      item: MemexProjectItem,
      suppress_hydro_events: T::Boolean,
    )
    .returns(MemexProjectColumn::Interface::Writeable::PartialResult)
  end
  private def delete_mysql_value(item:, suppress_hydro_events:)
    issue = item.issue_for_content
    issue_field = self.issue_field
    if issue && issue_field
      issue.issue_field_values.where(issue_field:).destroy_all
    end

    MemexProjectColumn::Interface::Writeable::PartialResult.success
  end

  sig do
    params(item: MemexProjectItem, new_value: T.untyped, actor: User, suppress_hydro_events: T::Boolean)
    .returns(MemexProjectColumn::Interface::Writeable::PartialResult)
  end
  private def change_mysql_value(item:, new_value:, actor:, suppress_hydro_events:)
    issue = item.issue_for_content
    issue_field = self.issue_field
    if issue.nil? || issue_field.nil?
      return MemexProjectColumn::Interface::Writeable::PartialResult.success
    end

    issue_field_value = issue.issue_field_values.find_or_initialize_by(issue_field:) do |new_field_value|
      new_field_value.repository = issue.repository
      new_field_value.data_type = issue_field.data_type
    end

    if issue_field_value.update(actor:, value: new_value)
      MemexProjectColumn::Interface::Writeable::PartialResult.success
    else
      MemexProjectColumn::Interface::Writeable::PartialResult.failure(
        "must be a valid value for #{data_type} column",
        attribute: :column_value
      )
    end
  end
end
