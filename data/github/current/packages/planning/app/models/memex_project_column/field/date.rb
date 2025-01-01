# typed: strict
# frozen_string_literal: true

class MemexProjectColumn::Field::Date < MemexProjectColumn::Field::Base
  include ElasticsearchDateQueryHelper
  include Helper::GenericField

  DATE_TITLE_FORMAT = "%b %-d, %Y"

  private_constant :DATE_TITLE_FORMAT

  sig { override.returns(T::Array[String]) }
  def self.register_processors
    [
      "MemexProjectColumn::Interface::Indexable::Processor::DateValueCreate",
      "MemexProjectColumn::Interface::Indexable::Processor::DateValueDestroy",
      "MemexProjectColumn::Interface::Indexable::Processor::DateValueUpdate",
    ]
  end

  sig { override.returns(Elastomer::Interfaces::Mapping::FieldDataType) }
  def self.elasticsearch_mapping
    Elastomer::Interfaces::Mapping::FieldDataTypes::Date.new(copy_to: Elastomer::Interfaces::Mapping::MemexProjectItem::FULL_TEXT_SEARCH_FIELDS)
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
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::DateValue)
  end
  def elasticsearch_document(item)
    data = item.column_values(columns: [self]).first
    dig_by = MemexProjectItem::ColumnDependency::COLUMN_VALUE_KEYS[self.data_type.to_sym]
    return unless data && dig_by

    data.dig(*dig_by)
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
      .params(
        value: String,
        context: Search::Memex::Context
      )
      .returns(T.nilable(T::Hash[T.untyped, T.untyped]))
  end
  def query_strategy(value:, context:)
    date_query(
      field_path: query_by_value_path,
      date_value: value,
      context:,
    )
  end

  sig { override.returns(String) }
  def group_by_value_path
    "field_values.#{self.class.value_name}"
  end
  alias_method :chart_by_value_path, :group_by_value_path
  alias_method :slice_by_value_path, :group_by_value_path
  alias_method :query_by_value_path, :group_by_value_path


  # Converts a millisecond epoch timestamp to a date string in the format "YYYY-MM-DD".
  #
  # EXAMPLE:
  #
  #   group_value("1636713600000") # => "2021-11-12"
  #
  # @param aggregation_bucket_key [String] When the item in question has a date value set for it,
  #  this a stringified millisecond epoch timestamp. Otherwise, if there is no date value for the
  #  item in question, then this is the sentinel value Groupable::MISSING_VALUE_GROUP_KEY.
  sig { override.params(aggregation_bucket_key: T.any(String, Numeric)).returns(String) }
  def group_value(aggregation_bucket_key)
    if aggregation_bucket_key == MemexProjectColumn::Interface::Groupable::MISSING_VALUE_GROUP_KEY
      return MemexProjectColumn::Interface::Groupable::MISSING_VALUE_GROUP_KEY
    end

    # "Z" is the time zone designator for UTC
    Time.at(aggregation_bucket_key.to_i / 1000.0, in: "Z").strftime("%Y-%m-%d")
  end
  alias_method :slice_value, :group_value

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

  # GraphQL expects a Ruby Date instance or nil so this override will help convert the Elasticsearch-stored value
  # to meet this input.
  sig { override.params(group_by_value: T.nilable(String)).returns(T.nilable(::Date)) }
  def graphql_value(group_by_value)
    # Calling super helps cleanse potential _noValue values
    translate_date(super(group_by_value))
  end

  # Override the base implementation so present dates are localized correctly.
  sig { override.params(group_by_value: T.nilable(String)).returns(String) }
  def graphql_title(group_by_value)
    graphql_value(group_by_value)&.strftime(DATE_TITLE_FORMAT) || super(group_by_value)
  end

  # We store dates as epoch to the MS precision, see for more info:
  # https://github.com/github/github/pull/294053/files#diff-0a32ea4cb4187f508d315d080ea17810212b0ef768f62209e42c8de9ebb61491R123-R125
  sig { params(value: T.nilable(String)).returns(T.nilable(::Date)) }
  private def translate_date(value)
    return if value.blank?

    # Since it is truly a date we can discard the time and timezone components and keep it as a pure Date
    # representation. Important to note here that the denominator is a float so we do not discard the
    # insignificant digits during arithmetic. This helps maintain millisecond precision.
    Time.at(value.to_i / 1000.0).utc.to_date
  end

  sig { override.returns(T::Boolean) }
  def self.writeable? = true

  sig do
    override.
      params(
        item: MemexProjectItem,
        prefilled_associations: T.nilable(MemexProjectItem::PrefilledAssociations),
        redacted_issue_ids: T::Array[Integer],
      ).
      returns(T.nilable(String))
  end
  def string_value(item, prefilled_associations: nil, redacted_issue_ids: [])
    data = item.column_values(columns: [self], prefilled_associations:, redacted_issue_ids:).first
    dig_by = MemexProjectItem::ColumnDependency::COLUMN_VALUE_KEYS[self.class.data_type]
    return unless data && dig_by

    data.dig(*dig_by)&.to_date&.strftime(DATE_TITLE_FORMAT)
  end

  sig { override.returns(T::Boolean) }
  def self.web_api_serializable? = true

  sig do
    override.
      params(
        item: MemexProjectItem,
        prefilled_associations: T.nilable(MemexProjectItem::PrefilledAssociations),
        redacted_issue_ids: T::Array[Integer],
      ).
      returns(T.nilable(MemexProjectColumnValue::Date))
  end
  def value(item, prefilled_associations: nil, redacted_issue_ids: [])
    value = T.cast(serializable(item, prefilled_associations:, redacted_issue_ids:), T.nilable(T::Hash[String, T.untyped]))
    return unless serializable_value = value&.dig("value")

    MemexProjectColumnValue::Date.new(value: serializable_value)
  end

  sig { override.returns(T::Boolean) }
  def self.rest_api_serializable? = true

  sig do
    override.
      params(
        item: MemexProjectItem,
        redacted_issue_ids: T::Array[Integer],
      )
      .returns(T.nilable(String))
  end
  def to_rest_api_hash(item, redacted_issue_ids: [])
    value = T.cast(serializable(item, redacted_issue_ids:), T.nilable(T::Hash[String, T.untyped]))

    value&.dig("value")
  end
end
