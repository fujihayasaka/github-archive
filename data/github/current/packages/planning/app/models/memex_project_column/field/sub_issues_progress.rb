# typed: strict
# frozen_string_literal: true

class MemexProjectColumn::Field::SubIssuesProgress < MemexProjectColumn::Field::Base
  include Helper::SpecialField

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

  sig do
    override
      .params(item: MemexProjectItem)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::SubIssuesProgressValue)
  end
  def elasticsearch_document(item)
    content_type = Elastomer::Interfaces::Document::MemexProjectItem::ContentType.deserialize(T.must(item.content_type))

    case content_type
    when Elastomer::Interfaces::Document::MemexProjectItem::ContentType::Issue
      content = item.content
      return unless (sub_issue_list = content&.sub_issue_list)
      return if sub_issue_list.total.zero?
      Elastomer::Interfaces::Document::SubIssuesProgress.new(
        total: sub_issue_list.total,
        percent_completed: sub_issue_list.percent_completed,
      )
    when Elastomer::Interfaces::Document::MemexProjectItem::ContentType::DraftIssue,
        Elastomer::Interfaces::Document::MemexProjectItem::ContentType::PullRequest
      nil
    else
      T.absurd(content_type)
    end
  end

  sig do
    override
      .params(context: Elastomer::Interfaces::Document::MemexProjectItem::SeedContext)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::SubIssuesProgressValue)
  end
  def seed_elasticsearch_document(context)
    content_type = context.content_type

    case content_type
    when Elastomer::Interfaces::Document::MemexProjectItem::ContentType::Issue
      total = rand(1..10)
      percent_completed = rand(0..100)
      Elastomer::Interfaces::Document::SubIssuesProgress.new(
        total: total,
        percent_completed: percent_completed,
      )
    when Elastomer::Interfaces::Document::MemexProjectItem::ContentType::DraftIssue,
        Elastomer::Interfaces::Document::MemexProjectItem::ContentType::PullRequest
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
end
