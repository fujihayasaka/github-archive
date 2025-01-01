# typed: strict
# frozen_string_literal: true

class MemexProjectColumn::Field::Text < MemexProjectColumn::Field::Base
  include Helper::GenericField

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
  alias_method :preload_web_api_response_data, :preload_elasticsearch_document_data
  alias_method :preload_rest_api_response_data, :preload_elasticsearch_document_data

  sig do
    override
      .params(item: MemexProjectItem)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::TextValue)
  end
  def elasticsearch_document(item)
    item.column_value(self)
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

  sig { override.returns(String) }
  def query_by_value_path
    "field_values.#{self.class.value_name}.lowercased_keyword"
  end

  # GraphQL expects a string and not nulls
  sig { override.params(group_by_value: T.nilable(String)).returns(T.nilable(String)) }
  def graphql_value(group_by_value)
    # Calling super helps cleanse potential _noValue values
    super(group_by_value).to_s
  end

  sig { override.returns(T::Boolean) }
  def self.writeable? = true

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
    return unless serializable_value = value&.dig("raw")

    MemexProjectColumnValue::Text.new(value: serializable_value)
  end

  sig { override.returns(T::Boolean) }
  def self.rest_api_serializable? = true

  sig do
    override.
     params(
       item: MemexProjectItem,
       redacted_issue_ids: T::Array[Integer],
     ).returns(T.nilable(T::Hash[String, T.untyped]))
  end
  def to_rest_api_hash(item, redacted_issue_ids: [])
    value = T.cast(serializable(item, redacted_issue_ids:), T.nilable(T::Hash[String, T.untyped]))
    return unless serializable_value = T.cast(value&.dig("raw"), T.nilable(String))

    {
      raw: serializable_value,
      html: to_html(serializable_value)
    }
  end

  sig { params(value: String).returns(T.nilable(String)) }
  def to_html(value)
    GitHub::Goomba::MemexTextColumnPipeline.to_html(value)
  end
end
