# typed: strict
# frozen_string_literal: true

class MemexProjectColumn::LinkedPullRequests < MemexProjectColumn::Field
  extend T::Sig
  include SpecialFieldHelpers

  TermQuery = Elastomer::Interfaces::Api::Search::Request::TermQuery
  WildcardQuery = Elastomer::Interfaces::Api::Search::Request::WildcardQuery

  sig { override.returns(T::Array[String]) }
  def self.register_processors
    [
      "MemexProjectColumn::Indexable::Processor::LinkedPullRequestsChange",
    ]
  end

  sig { override.returns(Elastomer::Interfaces::Mapping::FieldDataType) }
  def self.elasticsearch_mapping
    Elastomer::Interfaces::Mapping::FieldDataTypes::Object.new(properties: {
      number: Elastomer::Interfaces::Mapping::FieldDataTypes::KeywordMultiField.new(copy_to: Elastomer::Interfaces::Mapping::MemexProjectItem::FULL_TEXT_SEARCH_FIELDS),
      id: Elastomer::Interfaces::Mapping::FieldDataTypes::Long.new,
      repository_id: Elastomer::Interfaces::Mapping::FieldDataTypes::Long.new
    })
  end

  sig { override.params(items: T::Array[MemexProjectItem]).void }
  def preload_elasticsearch_document_data(items)
    preload_content_tree(items)

    issues = items.select(&:issue?).map(&:content).compact
    GitHub::PrefillAssociations.prefill_associations(issues, :close_issue_references)

    close_issue_references = issues.flat_map(&:close_issue_references).compact
    GitHub::PrefillAssociations.prefill_associations(close_issue_references, :pull_request)

    pull_requests = close_issue_references.map(&:pull_request).compact
    GitHub::PrefillAssociations.prefill_associations(pull_requests, :issue)
  end

  sig do
    override
      .params(item: MemexProjectItem)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::LinkedPullRequestsValue)
  end
  def elasticsearch_document(item)
    content_type = Elastomer::Interfaces::Document::MemexProjectItem::ContentType.deserialize(T.must(item.content_type))

    case content_type
    when Elastomer::Interfaces::Document::MemexProjectItem::ContentType::Issue
      item.content.close_issue_references.sort_by(&:pull_request_id).map do |r|
        Elastomer::Interfaces::Document::LinkedPullRequests.new(
          number: r.pull_request.number.to_s,
          id: r.pull_request_id,
          repository_id: r.pull_request.repository_id
        )
      end
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
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::LinkedPullRequestsValue)
  end
  def seed_elasticsearch_document(context)
    content_type = context.content_type

    case content_type
    when Elastomer::Interfaces::Document::MemexProjectItem::ContentType::Issue
      number = rand(1..1000)
      id = number + 1
      repository_id = number + 2
      [
        Elastomer::Interfaces::Document::LinkedPullRequests.new(
          number: number.to_s,
          id: id,
          repository_id: repository_id,
        )
      ]
    when Elastomer::Interfaces::Document::MemexProjectItem::ContentType::DraftIssue,
        Elastomer::Interfaces::Document::MemexProjectItem::ContentType::PullRequest
      nil
    else
      T.absurd(content_type)
    end
  end

  sig do
    override
      .params(
        values: T::Array[String],
        is_negated: T::Boolean,
        context: Search::Memex::Context
      )
      .returns(T::Hash[T.untyped, T.untyped])
  end
  def query_fragment(values:, is_negated:, context:)
    should_clauses = values.map do |value|
      {
        nested: {
          path: "field_values",
          query: if value.include?("*")
                   WildcardQuery.new(
                     field_path: "field_values.#{self.class.value_name}.number",
                     value: WildcardQuery::Value.new(value)
                   ).to_hash
                 else
                   TermQuery.new(field_path: "field_values.#{self.class.value_name}.number", value:).to_hash
                 end
        }
      }
    end

    wrap_query_fragment(should_clauses:, is_negated:)
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
                  "field_values.field_id": id
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
      sort_by: "field_values.#{self.class.value_name}.number.keyword",
    )
  end
end
