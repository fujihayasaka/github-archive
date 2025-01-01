# typed: strict
# frozen_string_literal: true

class MemexProjectColumn::Field::Text < MemexProjectColumn::Field::Base
  include Helper::GenericField

  TermQuery = Elastomer::Interfaces::Api::Search::Request::TermQuery
  WildcardQuery = Elastomer::Interfaces::Api::Search::Request::WildcardQuery

  sig { override.returns(T::Array[String]) }
  def self.register_processors
    [
      "MemexProjectColumn::Interface::Indexable::Processor::TextValueCreate",
      "MemexProjectColumn::Interface::Indexable::Processor::TextValueDestroy",
      "MemexProjectColumn::Interface::Indexable::Processor::TextValueUpdate"
    ]
  end

  sig { override.returns(Elastomer::Interfaces::Mapping::FieldDataType) }
  def self.elasticsearch_mapping
    Elastomer::Interfaces::Mapping::FieldDataTypes::KeywordMultiField.new(copy_to: Elastomer::Interfaces::Mapping::MemexProjectItem::FULL_TEXT_SEARCH_FIELDS)
  end

  sig { override.params(items: T::Array[MemexProjectItem]).void }
  def preload_elasticsearch_document_data(items)
    GitHub::PrefillAssociations.prefill_associations(items, :memex_project_column_values)
  end

  sig do
    override
      .params(item: MemexProjectItem)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::TextValue)
  end
  def elasticsearch_document(item)
    item.column_value(self, require_prefilled_associations: false)
  end

  sig do
    override
      .params(context: Elastomer::Interfaces::Document::MemexProjectItem::SeedContext)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::TextValue)
  end
  def seed_elasticsearch_document(context)
    context.set_value? ? Faker::Hacker.say_something_smart : nil
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
          query: {
            bool: {
              must: [
                {
                  term: {
                    "field_values.field_id": { value: id },
                  }
                },
                if value.include?("*")
                  WildcardQuery.new(
                    field_path: "field_values.#{self.class.value_name}.keyword",
                    value: WildcardQuery::Value.new(value),
                    case_insensitive: true,
                  ).to_hash
                else
                  TermQuery.new(
                    field_path: "field_values.#{self.class.value_name}.keyword",
                    value:,
                    case_insensitive: true,
                  ).to_hash
                end
              ]
            }
          }
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
          bool: {
            must: [
              {
                term: {
                  "field_values.field_id": {
                    value: id
                  },
                }
              },
              exists: {
                field: "field_values.#{self.class.value_name}.keyword"
              },
            ]
          }
        }
      }
    }
  end

  sig do
    override
      .params(direction: String)
      .returns(T::Hash[Symbol, String])
  end
  def sort_fragment(direction:)
    build_version_compatible_sort_fragment(
      direction: direction,
      sort_by: "field_values.#{self.class.value_name}.keyword"
    )
  end

  sig { override.returns(String) }
  def group_by_value_path
    "field_values.#{self.class.value_name}.keyword"
  end
  [:chart_by_value_path, :slice_by_value_path].each { |method| alias_method method, :group_by_value_path }

  # GraphQL expects a string and not nulls
  sig { override.params(group_by_value: T.nilable(String)).returns(T.nilable(String)) }
  def graphql_value(group_by_value)
    # Calling super helps cleanse potential _noValue values
    super(group_by_value).to_s
  end

  sig { override.returns(T::Boolean) }
  def self.writeable? = true

  # Returns a value that can be used to sort a MemexProjectItem by a given field.
  #
  # When querying for project items outside of ElasticSearch, this method returns the sortable value
  # for a field to regenerate the same sort order as ElasticSearch. The output for these methods should match
  # what ElasticSearch returns for the sorting order. Depending on the data type and direction, fields could
  # return the max or minimum 64-bit signed integer, a String, or a representation for Infinity.
  #
  # direction   - The direction to sort by, either :asc or :desc.
  # column_data - The data for the column to be sorted, this is JSON data stored in the column record, after
  #               extracting more specific information using the column data type to query through
  #               the MemexProjectItem::ColumnDependency::COLUMN_VALUE_KEYS Hash.
  #
  sig { override.params(direction: Symbol, column_data: T.untyped).returns(T.untyped) }
  def graphql_sortable_column_value(direction:, column_data:)
    column_data
  end
end
