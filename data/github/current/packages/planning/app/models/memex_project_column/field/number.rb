# typed: strict
# frozen_string_literal: true

class MemexProjectColumn::Field::Number < MemexProjectColumn::Field::Base
  include Helper::GenericField

  sig { override.returns(T::Array[String]) }
  def self.register_processors
    [
      "MemexProjectColumn::Interface::Indexable::Processor::NumberValueCreate",
      "MemexProjectColumn::Interface::Indexable::Processor::NumberValueDestroy",
      "MemexProjectColumn::Interface::Indexable::Processor::NumberValueUpdate"
    ]
  end

  sig { override.returns(Elastomer::Interfaces::Mapping::FieldDataType) }
  def self.elasticsearch_mapping
    Elastomer::Interfaces::Mapping::FieldDataTypes::Float.new(copy_to: Elastomer::Interfaces::Mapping::MemexProjectItem::FULL_TEXT_SEARCH_FIELDS)
  end

  sig { override.params(items: T::Array[MemexProjectItem]).void }
  def preload_elasticsearch_document_data(items)
    GitHub::PrefillAssociations.prefill_associations(items, :memex_project_column_values)
  end

  sig do
    override
      .params(item: MemexProjectItem)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::NumberValue)
  end
  def elasticsearch_document(item)
    item.group_by_value(self, require_prefilled_associations: false)
  end

  sig do
    override
      .params(
        value: String,
        context: Search::Memex::Context
      )
      .returns(T.nilable(T::Hash[T.untyped, T.untyped]))
  end
  def query_strategy(value:, context:)
    range_query(value)&.to_hash || match_query(value).to_hash
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
                  "field_values.field_id": id,
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

  sig do
    override
      .params(direction: String)
      .returns(T::Hash[T.untyped, T.untyped])
  end
  def sort_fragment(direction:)
    build_version_compatible_sort_fragment(
      direction: direction,
      sort_by: "field_values.#{self.class.value_name}",
    )
  end

  sig do
    override
      .params(context: Elastomer::Interfaces::Document::MemexProjectItem::SeedContext)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::NumberValue)
  end
  def seed_elasticsearch_document(context)
    context.set_value? ? Faker::Number.digit : nil
  end

  sig { override.returns(String) }
  def group_by_value_path
    "field_values.#{self.class.value_name}"
  end
  [
    :chart_by_value_path,
    :slice_by_value_path,
  ].each { |method| alias_method method, :group_by_value_path }
  # Sorbet doesn't understand the alias_method loop above
  alias_method :sum_by_value_path, :group_by_value_path
  alias_method :query_by_value_path, :group_by_value_path

  sig { override.params(group_by_value: T.nilable(String)).returns(T.nilable(Float)) }
  def graphql_value(group_by_value)
    # Calling super helps cleanse potential _noValue values
    super(group_by_value)&.to_f
  end

  sig { override.params(group_by_value: T.nilable(String)).returns(String) }
  def graphql_title(group_by_value)
    ActiveSupport::NumberHelper.number_to_rounded(
      graphql_value(group_by_value),
      precision: MemexProjectColumnValue::NUMBER_VALUE_PRECISION,
      strip_insignificant_zeros: true
    ) || super(group_by_value)
  end

  sig { override.returns(T::Boolean) }
  def self.writeable? = true

  sig { override.returns(T::Boolean) }
  def self.summable? = true

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
    if column_data
      column_data.to_d
    else
      direction == :asc ? Float::INFINITY : -Float::INFINITY
    end
  end
end
