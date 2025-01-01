# typed: strict
# frozen_string_literal: true

class MemexProjectColumn::Field::Number < MemexProjectColumn::Field::Base
  include ActiveSupport::NumberHelper
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
  alias_method :preload_web_api_response_data, :preload_elasticsearch_document_data
  alias_method :preload_rest_api_response_data, :preload_elasticsearch_document_data

  sig do
    override
      .params(item: MemexProjectItem)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::NumberValue)
  end
  def elasticsearch_document(item)
    item.group_by_value(self)
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
    formatted_value(graphql_value(group_by_value)) || super(group_by_value)
  end

  sig { override.returns(T::Boolean) }
  def self.writeable? = true

  sig { override.returns(T::Boolean) }
  def self.summable? = true

  sig { override.returns(T::Boolean) }
  def self.web_api_serializable? = true

  sig do
    override.
      params(
        item: MemexProjectItem,
        prefilled_associations: T.nilable(MemexProjectItem::PrefilledAssociations),
        redacted_issue_ids: T::Array[Integer],
      ).
      returns(T.nilable(ValueReturn))
  end
  def value(item, prefilled_associations: nil, redacted_issue_ids: [])
    value = T.cast(serializable(item, prefilled_associations:, redacted_issue_ids:), T.nilable(T::Hash[String, T.untyped]))
    return unless serializable_value = value&.dig("value")

    MemexProjectColumnValue::Number.new(value: serializable_value)
  end

  sig { override.returns(T::Boolean) }
  def self.rest_api_serializable? = true

  sig do
    override.
     params(
       item: MemexProjectItem,
       redacted_issue_ids: T::Array[Integer],
     ).
     returns(T.nilable(Numeric))
  end
  def to_rest_api_hash(item, redacted_issue_ids: [])
    value = serializable(item, redacted_issue_ids:)
    serializable_value = T.cast(value, T.nilable(T::Hash[String, T.untyped]))&.dig("value")

    return unless formatted_value = formatted_value(serializable_value)

    # After formatting the number to the desired precision, parse it as JSON
    # ensuring that the formatted value retains its precision as a number
    (JSON.parse(formatted_value) rescue 0)
  end

  sig do
    params(
      value: T.nilable(T.any(String, Numeric))
    )
    .returns(T.nilable(String))
  end
  def formatted_value(value)
    ActiveSupport::NumberHelper.number_to_rounded(
      value,
      precision: MemexProjectColumnValue::NUMBER_VALUE_PRECISION,
      strip_insignificant_zeros: true
    )
  end
end
