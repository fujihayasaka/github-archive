# typed: strict
# frozen_string_literal: true

class MemexProjectColumn::ParentIssue < MemexProjectColumn::Field
  extend T::Sig
  include SpecialFieldHelpers

  TermQuery = Elastomer::Interfaces::Api::Search::Request::TermQuery
  WildcardQuery = Elastomer::Interfaces::Api::Search::Request::WildcardQuery

  sig { override.returns(T::Array[String]) }
  def self.register_processors
    [
      "MemexProjectColumn::Indexable::Processor::SubIssueParentChange",
      "MemexProjectColumn::Indexable::Processor::ParentIssueTitleValueUpdate",
      "MemexProjectColumn::Indexable::Processor::RepositoryTransferParentIssue",
      "MemexProjectColumn::Indexable::Processor::RepositoryRenameParentIssue",
    ]
  end

  sig { override.returns(Elastomer::Interfaces::Mapping::FieldDataType) }
  def self.elasticsearch_mapping
    Elastomer::Interfaces::Mapping::FieldDataTypes::Object.new(properties: {
      id: Elastomer::Interfaces::Mapping::FieldDataTypes::Long.new,
      nwo_reference: Elastomer::Interfaces::Mapping::FieldDataTypes::KeywordMultiField.new(copy_to: Elastomer::Interfaces::Mapping::MemexProjectItem::FULL_TEXT_SEARCH_FIELDS),
      title: Elastomer::Interfaces::Mapping::FieldDataTypes::KeywordMultiField.new,
    })
  end

  sig { override.params(items: T::Array[MemexProjectItem]).void }
  def preload_elasticsearch_document_data(items)
    issue_items = items.select(&:issue?)
    preload_content_tree(issue_items)
    issues = issue_items.map(&:content).compact
    GitHub::PrefillAssociations.prefill_associations(issues, :parent_issue_relation)

    parent_relations = issues.map(&:parent_issue_relation).compact
    GitHub::PrefillAssociations.prefill_associations(parent_relations, :source)

    parents = parent_relations.map(&:source).compact
    GitHub::PrefillAssociations.prefill_associations(parents, { repository: :owner }, available_records: issue_items.map(&:repository))
  end

  sig do
    override
      .params(item: MemexProjectItem)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::ParentIssueValue)
  end
  def elasticsearch_document(item)
    content_type = Elastomer::Interfaces::Document::MemexProjectItem::ContentType.deserialize(T.must(item.content_type))

    case content_type
    when Elastomer::Interfaces::Document::MemexProjectItem::ContentType::Issue
      content = item.content
      return unless (relation = content&.parent_issue_relation)
      return unless (parent = relation&.source)
      Elastomer::Interfaces::Document::ParentIssue.new(
        id: parent.id,
        nwo_reference: parent.nwo_reference(nil),
        title: parent.title,
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
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::ParentIssueValue)
  end
  def seed_elasticsearch_document(context)
    content_type = context.content_type

    case content_type
    when Elastomer::Interfaces::Document::MemexProjectItem::ContentType::Issue
      id = rand(1..1000)
      repository = id + 1
      owner_display_login = id + 2
      Elastomer::Interfaces::Document::ParentIssue.new(
        id: id,
        nwo_reference: "owner#{owner_display_login}/repository#{repository}##{id}",
        title: "issue ##{id}",
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
      .params(values: T::Array[String], is_negated: T::Boolean, context: Search::Memex::Context)
      .returns(T::Hash[T.untyped, T.untyped])
  end
  def query_fragment(values:, is_negated:, context:)
    should_clauses = values.map do |value|
      {
        nested: {
          path: "field_values",
          query: if value.include?("*")
                   WildcardQuery.new(
                     field_path: "field_values.#{self.class.value_name}.nwo_reference.keyword",
                     value: WildcardQuery::Value.new(value),
                     case_insensitive: true,
                   ).to_hash
                 else
                   TermQuery.new(
                     field_path: "field_values.#{self.class.value_name}.nwo_reference.keyword",
                     value:,
                     case_insensitive: true,
                   ).to_hash
                 end
        }
      }
    end

    wrap_query_fragment(should_clauses:, is_negated:)
  end

  sig do
    override
      .params(direction: String)
      .returns(T::Hash[T.untyped, T.untyped])
  end
  def sort_fragment(direction:)
    build_version_compatible_sort_fragment(
      direction: direction,
      sort_by: "field_values.#{self.class.value_name}.title.keyword",
    )
  end

  sig { override.returns(T::Hash[T.untyped, T.untyped]) }
  def existence_fragment
    {
      nested: {
        path: "field_values",
        query: {
          bool: {
            filter: [
              {
                term: {
                  "field_values.field_id": id
                }
              },
              exists: {
                field: "field_values.#{self.class.value_name}"
              },
            ]
          }
        }
      }
    }
  end

  sig { override.returns(String) }
  def group_by_value_path
    "field_values.#{self.class.value_name}.nwo_reference.keyword"
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
      .returns(T::Hash[Integer, T.all(Issue, Groupable::Metadata)])
  end
  def preload_group_metadata_objects(metadata_object_ids)
    issues = Issue.where(id: metadata_object_ids).includes(repository: :owner).index_by(&:id)
  end
  alias_method :preload_slice_metadata_objects, :preload_group_metadata_objects
end
