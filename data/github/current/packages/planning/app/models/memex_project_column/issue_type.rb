# typed: strict
# frozen_string_literal: true

class MemexProjectColumn::IssueType < MemexProjectColumn::Field
  extend T::Sig
  include SpecialFieldHelpers

  TermQuery = Elastomer::Interfaces::Api::Search::Request::TermQuery
  WildcardQuery = Elastomer::Interfaces::Api::Search::Request::WildcardQuery

  sig { override.returns(T::Array[String]) }
  def self.register_processors
    [
      "MemexProjectColumn::Indexable::Processor::IssueUpdateIssueType",
      "MemexProjectColumn::Indexable::Processor::IssueTypeDestroy",
      "MemexProjectColumn::Indexable::Processor::IssueTypeUpdate",
      "MemexProjectColumn::Indexable::Processor::RepositoryIssueTypeChange",
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
    preload_content_tree(items)

    issues = items.select(&:issue?).map(&:content)

    # The batch_method on issues for issue_type determines if the issue type is enabled or if the issue's
    # repository is excluded from issue types. If Issue#issue_type returns nil, the issue type is not enabled or does
    # not have one set.
    GitHub::PrefillAssociations.prefill_batch_method(issues, :issue_type)
  end

  sig do
    override
      .params(item: MemexProjectItem)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::IssueTypeValue)
  end
  def elasticsearch_document(item)
    return unless content = item.content
    content_type = Elastomer::Interfaces::Document::MemexProjectItem::ContentType.deserialize(T.must(item.content_type))

    case content_type
    when Elastomer::Interfaces::Document::MemexProjectItem::ContentType::Issue
      return unless (issue_type = content&.issue_type)
      return unless (repository = content&.repository.present?)

      Elastomer::Interfaces::Document::IssueType.new(
        name: issue_type.name,
        id: issue_type.id,
      )
    when Elastomer::Interfaces::Document::MemexProjectItem::ContentType::DraftIssue,
      Elastomer::Interfaces::Document::MemexProjectItem::ContentType::PullRequest
      nil
    else
      T.absurd(content_type)
    end
  end

  sig do
    override
      .params(context: Elastomer::Interfaces::Document::MemexProjectItem::SeedContext)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::IssueTypeValue)
  end
  def seed_elasticsearch_document(context)
    content_type = context.content_type

    case content_type
    when Elastomer::Interfaces::Document::MemexProjectItem::ContentType::Issue
      if context.set_value?
        issue_type = T.must(Array(context.issue_types.sample).first)
        Elastomer::Interfaces::Document::IssueType.new(
          id: issue_type.id,
          name: issue_type.name,
        )
      end
    when Elastomer::Interfaces::Document::MemexProjectItem::ContentType::PullRequest,
        Elastomer::Interfaces::Document::MemexProjectItem::ContentType::DraftIssue
      nil
    else
      T.absurd(content_type)
    end
  end

  sig do
    override
      .params(
        values: T::Array[String],
        is_negated: T::Boolean,
        context: Search::Memex::Context
      )
      .returns(T::Hash[T.untyped, T.untyped])
  end
  def query_fragment(values:, is_negated:, context:)
    should_clauses = values.map do |value|
      {
        nested: {
          path: "field_values",
          query: wildcard_query(value)&.to_hash || term_query(value).to_hash
        }
      }
    end

    wrap_query_fragment(should_clauses:, is_negated:)
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
  alias_method :slice_by_value_path, :group_by_value_path

  sig { override.returns(T::Boolean) }
  def has_group_metadata? = true

  sig { override.returns(String) }
  def group_by_metadata_id_path
    "field_values.#{self.class.value_name}.id"
  end
  alias_method :slice_by_metadata_id_path, :group_by_metadata_id_path

  sig do
    override
      .params(metadata_object_ids: T::Array[Integer])
      .returns(T::Hash[Integer, T.all(IssueType, Groupable::Metadata)])
  end
  def preload_group_metadata_objects(metadata_object_ids)
    ::IssueType.where(id: metadata_object_ids).index_by(&:id)
  end
  alias_method :preload_slice_metadata_objects, :preload_group_metadata_objects

  sig { params(value: String).returns(T.nilable(WildcardQuery)) }
  private def wildcard_query(value)
    return nil unless value.include?("*")

    WildcardQuery.new(
      field_path: "field_values.#{self.class.value_name}.name.keyword",
      value: WildcardQuery::Value.new(value),
      case_insensitive: true,
    )
  end

  sig { params(value: String).returns(TermQuery) }
  private def term_query(value)
    TermQuery.new(
      field_path: "field_values.#{self.class.value_name}.name.keyword",
      value:,
      case_insensitive: true
    )
  end
end
