# typed: strict
# frozen_string_literal: true

class MemexProjectColumn::Field::Repository < MemexProjectColumn::Field::Base
  include Helper::SpecialField

  TermQuery = Elastomer::Interfaces::Api::Search::Request::TermQuery
  WildcardQuery = Elastomer::Interfaces::Api::Search::Request::WildcardQuery

  sig { override.returns(T::Array[String]) }
  def self.register_processors
    [
      "MemexProjectColumn::Interface::Indexable::Processor::RepositoryRename",
      "MemexProjectColumn::Interface::Indexable::Processor::RepositoryTransfer"
    ]
  end

  sig { override.returns(Symbol) }
  def query_slug
    :repo
  end

  sig { override.returns(Elastomer::Interfaces::Mapping::FieldDataType) }
  def self.elasticsearch_mapping
    Elastomer::Interfaces::Mapping::FieldDataTypes::Object.new(properties: {
      id: Elastomer::Interfaces::Mapping::FieldDataTypes::Long.new,
      owner_id: Elastomer::Interfaces::Mapping::FieldDataTypes::Long.new,
      owner_type: Elastomer::Interfaces::Mapping::FieldDataTypes::Keyword.new,
      full_name: Elastomer::Interfaces::Mapping::FieldDataTypes::KeywordMultiField.new(copy_to: Elastomer::Interfaces::Mapping::MemexProjectItem::FULL_TEXT_SEARCH_FIELDS)
    })
  end

  sig { override.params(items: T::Array[MemexProjectItem]).void }
  def preload_elasticsearch_document_data(items)
    preload_content_tree(items)
    GitHub::PrefillAssociations.prefill_associations(items.map(&:repository), [:owner])
  end

  sig { override.params(item: MemexProjectItem).returns(Elastomer::Interfaces::Document::MemexProjectItem::RepositoryValue) }
  def elasticsearch_document(item)
    content_type = Elastomer::Interfaces::Document::MemexProjectItem::ContentType.deserialize(T.must(item.content_type))

    case content_type
    when Elastomer::Interfaces::Document::MemexProjectItem::ContentType::Issue,
        Elastomer::Interfaces::Document::MemexProjectItem::ContentType::PullRequest
      Elastomer::Interfaces::Document::Repository.new(
        id: item.repository_id,
        owner_id: T.must(item.repository).owner_id,
        owner_type: T.must(item.repository).owner&.type,
        full_name: item.repository&.full_name
      )
    when Elastomer::Interfaces::Document::MemexProjectItem::ContentType::DraftIssue
      nil
    else
      T.absurd(content_type)
    end
  end

  sig do
    override
      .params(context: Elastomer::Interfaces::Document::MemexProjectItem::SeedContext)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::RepositoryValue)
  end
  def seed_elasticsearch_document(context)
    content_type = context.content_type

    case content_type
    when Elastomer::Interfaces::Document::MemexProjectItem::ContentType::Issue,
        Elastomer::Interfaces::Document::MemexProjectItem::ContentType::PullRequest
      Elastomer::Interfaces::Document::Repository.new(
        id: Faker::Number.digit,
        owner_id: Faker::Number.digit,
        owner_type: %w(User Organization).sample,
        full_name: "#{Faker::Internet.username}/#{Faker::Lorem.word}"
      )
    when Elastomer::Interfaces::Document::MemexProjectItem::ContentType::DraftIssue
      nil
    else
      T.absurd(content_type)
    end
  end

  sig do
    override
      .params(direction: String)
      .returns(T::Hash[T.untyped, T.untyped])
  end
  def sort_fragment(direction:)
    build_version_compatible_sort_fragment(
      direction: direction,
      sort_by: "field_values.#{self.class.value_name}.full_name.keyword",
    )
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
            field: "field_values.#{self.class.value_name}.full_name"
          }
        }
      }
    }
  end

  sig { override.returns(String) }
  def group_by_value_path
    "field_values.#{self.class.value_name}.full_name.keyword"
  end
  [:chart_by_value_path, :slice_by_value_path].each { |method| alias_method method, :group_by_value_path }

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
      .returns(T::Hash[Integer, T.all(Repository, Interface::Groupable::Metadata)])
  end
  def preload_group_metadata_objects(metadata_object_ids)
    ::Repository.where(id: metadata_object_ids).index_by(&:id)
  end
  alias_method :preload_slice_metadata_objects, :preload_group_metadata_objects

  sig { params(value: String).returns(T.nilable(WildcardQuery)) }
  private def wildcard_query(value)
    return nil unless value.include?("*")

    WildcardQuery.new(
      field_path: "field_values.#{self.class.value_name}.full_name.keyword",
      value: WildcardQuery::Value.new(value),
      case_insensitive: true,
    )
  end

  sig { params(value: String).returns(TermQuery) }
  private def term_query(value)
    TermQuery.new(
      field_path: "field_values.#{self.class.value_name}.full_name.keyword",
      value:,
      case_insensitive: true,
    )
  end
end
