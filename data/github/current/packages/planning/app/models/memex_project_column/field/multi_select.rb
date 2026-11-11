# typed: strict
# frozen_string_literal: true

# Stub field class for generic (project-native) multi-select columns.
#
# This class exists so that the Elasticsearch mapping for `multi_select_value` is registered
# alongside the issue-field variant (`issue_field_multi_select_value`). When generic multi-select
# support is enabled:
#
#   1. Add "multi_select" to `GENERIC_TYPES` in `MemexProjectColumn`.
#   2. Include `Helper::GenericField` here and implement processors, query, sort, group, and
#      serialization methods following the pattern in `Field::SingleSelect`.
#   3. Flip `writeable?`, `queryable?`, and `web_api_serializable?` to `true`.
class MemexProjectColumn::Field::MultiSelect < MemexProjectColumn::Field::Base
  sig { override.returns(T::Boolean) }
  def self.web_api_serializable? = false

  sig { override.returns(T::Boolean) }
  def self.rest_api_serializable? = false

  sig { override.returns(T::Boolean) }
  def self.writeable? = false

  sig { override.returns(T::Boolean) }
  def self.queryable? = false

  sig { override.returns(T::Boolean) }
  def self.disabled? = true

  sig { override.returns(T::Array[String]) }
  def self.register_processors
    []
  end

  sig { override.returns(Elastomer::Interfaces::Mapping::FieldDataType) }
  def self.elasticsearch_mapping
    Elastomer::Interfaces::Mapping::FieldDataTypes::Object.new(properties: {
      id: Elastomer::Interfaces::Mapping::FieldDataTypes::Keyword.new,
      name: Elastomer::Interfaces::Mapping::FieldDataTypes::KeywordMultiField.new(
        copy_to: Elastomer::Interfaces::Mapping::MemexProjectItem::FULL_TEXT_SEARCH_FIELDS,
      ),
    })
  end

  sig { override.params(items: T::Array[MemexProjectItem]).void }
  def preload_elasticsearch_document_data(items)
    # no-op until generic multi-select is enabled
  end

  sig do
    override
      .params(item: MemexProjectItem)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::MultiSelectValue)
  end
  def elasticsearch_document(item)
    # no-op until generic multi-select is enabled
    nil
  end
end
