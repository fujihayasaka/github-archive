# typed: strict
# frozen_string_literal: true

class MemexProjectColumn::Field::IssueField::MultiSelect < MemexProjectColumn::Field::IssueField::Base
  DEFAULT_PRIORITY = 500

  INDEXING_FLAG = :memex_issue_field_multi_select_indexing
  CONSISTENCY_SCORE_FLAG = :memex_issue_field_multi_select_include_consistency_score

  sig { override.returns(T::Boolean) }
  def self.indexable?
    FeatureFlag.vexi.enabled?(INDEXING_FLAG, default: false)
  end

  sig { override.returns(T::Boolean) }
  def self.web_api_serializable? = false

  sig { override.returns(T::Boolean) }
  def self.rest_api_serializable? = false

  sig { override.returns(T::Boolean) }
  def self.writeable? = false

  sig { override.returns(T::Boolean) }
  def self.queryable? = false

  sig { override.returns(T::Array[String]) }
  def self.register_processors
    [
      "MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateIssueFieldMultiSelectValue",
    ]
  end

  sig { override.params(items: T::Array[MemexProjectItem]).void }
  def preload_elasticsearch_document_data(items)
    supported_items = items.select(&:issue?)

    preload_content_tree(supported_items)

    issues = supported_items.map(&:issue).compact
    MemexProjectItemPrefiller.preload_issue_field_values_with_repo_id(issues, extra_associations: { issue_field: :options })
  end

  sig { override.returns(Elastomer::Interfaces::Mapping::FieldDataType) }
  def self.elasticsearch_mapping
    Elastomer::Interfaces::Mapping::FieldDataTypes::Object.new(
      properties: {
        id: Elastomer::Interfaces::Mapping::FieldDataTypes::Long.new,
        name: Elastomer::Interfaces::Mapping::FieldDataTypes::KeywordMultiField.new(
          copy_to: Elastomer::Interfaces::Mapping::MemexProjectItem::FULL_TEXT_SEARCH_FIELDS,
        ),
        priority: Elastomer::Interfaces::Mapping::FieldDataTypes::Long.new,
      },
    )
  end

  sig do
    override
      .params(item: MemexProjectItem)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::IssueFieldMultiSelectValue)
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

      issue_field_value = T.cast(issue_field_value, IssueFieldMultiSelectValue)
      options = issue_field_value.options
      return if options.empty?

      IssueFieldOption.sorted_options(options).map do |option|
        Elastomer::Interfaces::Document::IssueFieldMultiSelect.new(
          id: option.id,
          name: option.name,
          priority: option.priority || DEFAULT_PRIORITY,
        )
      end
    when MemexProjectItem::ContentType::DraftIssue,
      MemexProjectItem::ContentType::PullRequest,
      MemexProjectItem::ContentType::AgentTask

      nil
    else
      T.absurd(content_type)
    end
  end
end
