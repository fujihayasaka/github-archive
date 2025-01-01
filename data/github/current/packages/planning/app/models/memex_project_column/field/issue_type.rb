# typed: strict
# frozen_string_literal: true

class MemexProjectColumn::Field::IssueType < MemexProjectColumn::Field::Base
  include Interface::SpecialTypeSerializable

  sig { override.returns(T::Array[MemexProjectItem::ContentType]) }
  def self.supported_content_types = [MemexProjectItem::ContentType::Issue]

  sig { override.returns(T::Array[String]) }
  def self.register_processors
    [
      "MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateIssueType",
      "MemexProjectColumn::Interface::Indexable::Processor::IssueTypeDestroy",
      "MemexProjectColumn::Interface::Indexable::Processor::IssueTypeUpdate",
      "MemexProjectColumn::Interface::Indexable::Processor::RepositoryIssueTypeChange",
    ]
  end

  sig { override.returns(Elastomer::Interfaces::Mapping::FieldDataType) }
  def self.elasticsearch_mapping
    Elastomer::Interfaces::Mapping::FieldDataTypes::Object.new(properties: {
      id: Elastomer::Interfaces::Mapping::FieldDataTypes::Long.new,
      name: Elastomer::Interfaces::Mapping::FieldDataTypes::KeywordMultiField.new(copy_to: Elastomer::Interfaces::Mapping::MemexProjectItem::FULL_TEXT_SEARCH_FIELDS),
    })
  end

  sig { override.params(items: T::Array[MemexProjectItem]).void }
  def preload_elasticsearch_document_data(items)
    supported_items = items.select(&:issue?)

    preload_content_tree(supported_items)

    issues = supported_items.map(&:content).compact

    # The batch_method on issues for issue_type determines if the issue type is enabled or if the issue's
    # repository is excluded from issue types. If Issue#issue_type returns nil, the issue type is not enabled or does
    # not have one set.
    GitHub::PrefillAssociations.prefill_batch_method(issues, :issue_type)
  end
  alias_method :preload_web_api_response_data, :preload_elasticsearch_document_data
  alias_method :preload_rest_api_response_data, :preload_elasticsearch_document_data

  sig do
    override
      .params(item: MemexProjectItem)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::IssueTypeValue)
  end
  def elasticsearch_document(item)
    return unless content = item.content # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    content_type = MemexProjectItem::ContentType.deserialize(item.content_type)

    case content_type
    when MemexProjectItem::ContentType::Issue
      issue = T.cast(content, Issue)
      return unless (issue_type = issue.issue_type)
      return unless (repository = issue.repository.present?)

      Elastomer::Interfaces::Document::IssueType.new(
        name: issue_type.name,
        id: issue_type.id,
      )
    when MemexProjectItem::ContentType::DraftIssue,
      MemexProjectItem::ContentType::PullRequest
      nil
    else
      T.absurd(content_type)
    end
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
      if prefilled_associations
        prefilled_associations.issue_type(item)
      else
        issue = T.cast(item.content, Issue) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        issue.issue_type
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
        query: {
          exists: {
            field: "field_values.#{self.class.value_name}.id"
          }
        }
      }
    }
  end

  sig do
    override
      .params(direction: String)
      .returns(T::Hash[T.untyped, T.untyped])
  end
  def sort_fragment(direction:)
    build_version_compatible_sort_fragment(
      direction: direction,
      sort_by: "field_values.#{self.class.value_name}.name.keyword",
    )
  end

  sig { override.returns(String) }
  def group_by_value_path
    "field_values.#{self.class.value_name}.name.keyword"
  end
  [:chart_by_value_path, :slice_by_value_path].each { |method| alias_method method, :group_by_value_path }

  sig { override.returns(String) }
  def query_by_value_path
    "field_values.#{self.class.value_name}.name.lowercased_keyword"
  end

  sig { override.returns(T::Boolean) }
  def has_group_metadata? = true

  sig { override.returns(String) }
  def metadata_id_path
    "field_values.#{self.class.value_name}.id"
  end

  sig do
    override
      .params(metadata_object_ids: T::Array[Integer])
      .returns(T::Hash[Integer, T.all(IssueType, IDataSource)])
  end
  def preload_metadata_objects(metadata_object_ids)
    ::IssueType.where(id: metadata_object_ids).index_by(&:id)
  end

  sig { override.returns(T::Boolean) }
  def self.writeable? = true

  sig do
    override
    .params(
      item: MemexProjectItem,
      new_value: T.untyped,
      actor: User,

      # This parameter is required by the abstract interface, but it is not and should not be used in this method
      # because we are not at liberty to suppress Hydro events for labels (they are part of the Issues service
      # rather than the Projects service; this method is just a convenience for interacting with labels from
      # within Projects).
      suppress_hydro_events: T::Boolean)
    .returns(Interface::Writeable::PartialResult)
  end
  private def update_mysql_field_value(item:, new_value:, actor:, suppress_hydro_events:)
    content = item.content # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    unless content.is_a?(Issue)
      return Interface::Writeable::PartialResult.failure("Only issues are supported")
    end

    unless content.can_set_type?(actor: actor)
      return Interface::Writeable::PartialResult.failure("You do not have permission to set the issue type for this item")
    end

    unless content.update(issue_type_id: new_value) # domain-isolation-query-violation:ignore:packages/issues (UPDATE)
      return Interface::Writeable::PartialResult.failure(content.errors.full_messages.to_sentence)
    end

    Interface::Writeable::PartialResult.success
  end

  sig { override.returns(T::Boolean) }
  def self.rest_api_serializable? = true

  sig do
    override.
     params(
       item: MemexProjectItem,
       redacted_issue_ids: T::Array[Integer],
     ).
     returns(T.nilable(T::Hash[String, T.untyped]))
  end
  def to_rest_api_hash(item, redacted_issue_ids: [])
    return unless issue_type = serializable(item, redacted_issue_ids:)

    Api::Serializer.serialize(:type_hash, issue_type)
  end
end
