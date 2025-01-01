# typed: strict
# frozen_string_literal: true

class MemexProjectColumn::Field::SubIssuesProgress < MemexProjectColumn::Field::Base
  include Interface::SpecialTypeSerializable

  sig { override.returns(T::Array[MemexProjectItem::ContentType]) }
  def self.supported_content_types = [MemexProjectItem::ContentType::Issue]

  sig { override.returns(T::Array[String]) }
  def self.register_processors
    [
      "MemexProjectColumn::Interface::Indexable::Processor::SubIssueListRecalculate",
    ]
  end

  sig { override.returns(Elastomer::Interfaces::Mapping::FieldDataType) }
  def self.elasticsearch_mapping
    Elastomer::Interfaces::Mapping::FieldDataTypes::Object.new(properties: {
      total: Elastomer::Interfaces::Mapping::FieldDataTypes::Long.new,
      percent_completed: Elastomer::Interfaces::Mapping::FieldDataTypes::Long.new,
    })
  end

  sig { override.params(items: T::Array[MemexProjectItem]).void }
  def preload_elasticsearch_document_data(items)
    issue_items = items.select(&:issue?)
    preload_content_tree(issue_items)
    issues = issue_items.map(&:content).compact
    GitHub::PrefillAssociations.prefill_associations(issues, :sub_issue_list)
  end
  alias_method :preload_web_api_response_data, :preload_elasticsearch_document_data
  alias_method :preload_rest_api_response_data, :preload_elasticsearch_document_data

  sig do
    override
      .params(item: MemexProjectItem)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::SubIssuesProgressValue)
  end
  def elasticsearch_document(item)
    content_type = MemexProjectItem::ContentType.deserialize(item.content_type)

    case content_type
    when MemexProjectItem::ContentType::Issue
      content = T.cast(item.content, T.nilable(Issue)) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      return unless (sub_issue_list = content&.sub_issue_list)
      return if sub_issue_list.total.zero?
      Elastomer::Interfaces::Document::SubIssuesProgress.new(
        total: sub_issue_list.total,
        percent_completed: sub_issue_list.percent_completed,
      )
    when MemexProjectItem::ContentType::DraftIssue,
        MemexProjectItem::ContentType::PullRequest
      nil
    else
      T.absurd(content_type)
    end
  end

  sig do
    override.
      params(
        item: MemexProjectItem,
        prefilled_associations: T.nilable(MemexProjectItem::PrefilledAssociations),
        redacted_issue_ids: T::Array[Integer],
      ).
      returns(T.nilable(MemexProjectColumn::IDataSource))
  end
  def serializable(item, prefilled_associations: nil, redacted_issue_ids: [])
    content_type = MemexProjectItem::ContentType.deserialize(item.content_type)

    case content_type
    when MemexProjectItem::ContentType::Issue
      if prefilled_associations
        prefilled_associations.sub_issues_progress(item)
      else
        issue = T.cast(item.content, Issue) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        issue.sub_issue_list
      end
    when MemexProjectItem::ContentType::PullRequest,
      MemexProjectItem::ContentType::DraftIssue
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
      sort_by: "field_values.#{self.class.value_name}.percent_completed",
    )
  end

  sig { override.returns(String) }
  def query_by_value_path
    "field_values.#{self.class.value_name}.percent_completed"
  end

  sig do
    override
    .params(value: String, context: Search::Memex::Context)
    .returns(T.nilable(T::Hash[T.untyped, T.untyped]))
  end
  def query_strategy(value:, context:)
    range_query(value)&.to_hash || match_query(value).to_hash
  end

  # SubIssuesProgress existence is determined by both the existence of the total field and its value being greater than 0
  sig { override.returns(T::Hash[T.untyped, T.untyped]) }
  def existence_fragment
    {
      nested: {
        path: "field_values",
        query: {
          bool: {
            must: [
              {
                range: {
                  "field_values.#{self.class.value_name}.total": {
                    gt: 0
                  }
                }
              },
              exists: {
                field: "field_values.#{self.class.value_name}.total"
              }
            ]
          }
        }
      }
    }
  end

  sig { override.returns(T::Boolean) }
  def self.rest_api_serializable? = true

  sig do
    override.
     params(
       item: MemexProjectItem,
       redacted_issue_ids: T::Array[Integer],
     ).
     returns(T.nilable(T::Hash[Symbol, Integer]))
  end
  def to_rest_api_hash(item, redacted_issue_ids: [])
    return unless sub_issue_list = T.cast(serializable(item, redacted_issue_ids:), T.nilable(SubIssueList))

    sub_issue_list.to_h
  end
end
