# typed: strict
# frozen_string_literal: true

class MemexProjectColumn::Field::IssueField::Text < MemexProjectColumn::Field::IssueField::Base
  sig { override.returns(T::Boolean) }
  def self.writeable? = true

  sig { override.returns(T::Boolean) }
  def self.rest_api_serializable? = true

  sig { override.returns(T::Array[String]) }
  def self.register_processors
    [
      "MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateIssueFieldTextValue",
    ]
  end

  sig { override.returns(Elastomer::Interfaces::Mapping::FieldDataType) }
  def self.elasticsearch_mapping
    Elastomer::Interfaces::Mapping::FieldDataTypes::KeywordMultiField.new(
      copy_to: Elastomer::Interfaces::Mapping::MemexProjectItem::FULL_TEXT_SEARCH_FIELDS,
    )
  end

  sig { override.returns(String) }
  def query_by_value_path
    "field_values.#{self.class.value_name}.lowercased_keyword"
  end

  sig do
    override
      .params(direction: String)
      .returns(T::Hash[Symbol, String])
  end
  def sort_fragment(direction:)
    build_version_compatible_sort_fragment(
      direction:,
      sort_by: "field_values.#{self.class.value_name}.keyword"
    )
  end

  sig { override.returns(String) }
  def group_by_value_path
    "field_values.#{self.class.value_name}.keyword"
  end

  sig { override.returns(String) }
  def chart_by_value_path
    group_by_value_path
  end

  sig { override.returns(String) }
  def slice_by_value_path
    group_by_value_path
  end

  sig { override.params(items: T::Array[MemexProjectItem]).void }
  def preload_elasticsearch_document_data(items)
    supported_items = items.select(&:issue?)

    preload_content_tree(supported_items)

    issues = supported_items.map(&:issue).compact
    GitHub::PrefillAssociations.prefill_associations(issues, :issue_field_values)
  end
  alias_method :preload_rest_api_response_data, :preload_elasticsearch_document_data

  sig do
    override.
     params(
       item: MemexProjectItem,
       redacted_issue_ids: T::Array[Integer],
     ).returns(T.nilable(T::Hash[String, T.untyped]))
  end
  def to_rest_api_hash(item, redacted_issue_ids: [])
    issue_field_value = T.cast(serializable(item, redacted_issue_ids:), T.nilable(IssueFieldTextValue))
    return unless issue_field_value&.memex_column_value_present?

    memex_project_column_value = issue_field_value.memex_project_column_value
    memex_project_column_value.to_hash
  end
end
