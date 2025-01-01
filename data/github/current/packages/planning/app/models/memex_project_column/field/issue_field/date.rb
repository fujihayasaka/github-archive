# typed: strict
# frozen_string_literal: true

class MemexProjectColumn::Field::IssueField::Date < MemexProjectColumn::Field::IssueField::Base
  include ElasticsearchDateQueryHelper

  sig { override.returns(T::Boolean) }
  def self.writeable? = true

  sig { override.returns(T::Array[String]) }
  def self.register_processors
    [
      "MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateIssueFieldDateValue",
    ]
  end

  sig do
    override
      .overridable
      .params(item: MemexProjectItem)
      .returns(T.nilable(Elastomer::Interfaces::Document::MemexProjectItem::DateValue))
  end
  def elasticsearch_document(item)
    content_type = MemexProjectItem::ContentType.deserialize(item.content_type)

    case content_type
    when MemexProjectItem::ContentType::Issue
      return unless issue_field?

      issue = T.cast(item.content, Issue) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      issue_field_value = issue.issue_field_values.find do |field_value|
        field_value.issue_field_id == issue_field_id
      end
      return unless issue_field_value

      issue_field_value.value.iso8601
    when MemexProjectItem::ContentType::DraftIssue,
      MemexProjectItem::ContentType::PullRequest

      nil
    else
      T.absurd(content_type)
    end
  end

  sig { override.returns(Elastomer::Interfaces::Mapping::FieldDataType) }
  def self.elasticsearch_mapping
    Elastomer::Interfaces::Mapping::FieldDataTypes::Date.new(
      copy_to: Elastomer::Interfaces::Mapping::MemexProjectItem::FULL_TEXT_SEARCH_FIELDS,
    )
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
  def query_by_value_path
    "field_values.#{self.class.value_name}"
  end

  sig do
    override
      .params(direction: String)
      .returns(T::Hash[Symbol, String])
  end
  def sort_fragment(direction:)
    build_version_compatible_sort_fragment(
      direction:,
      sort_by: query_by_value_path,
    )
  end

  sig { override.returns(String) }
  def group_by_value_path
    query_by_value_path
  end

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
  alias_method :preload_web_api_response_data, :preload_elasticsearch_document_data
end
