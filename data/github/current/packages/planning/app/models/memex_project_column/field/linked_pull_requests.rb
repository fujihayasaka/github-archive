# typed: strict
# frozen_string_literal: true

class MemexProjectColumn::Field::LinkedPullRequests < MemexProjectColumn::Field::Base
  include Interface::SpecialTypeSerializable

  sig { override.returns(T::Array[String]) }
  def self.register_processors
    [
      "MemexProjectColumn::Interface::Indexable::Processor::LinkedPullRequestsChange",
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

    issues = T.cast(items.select(&:issue?).map(&:content).compact, T::Array[Issue])
    GitHub::PrefillAssociations.prefill_associations(issues, :close_issue_references)

    close_issue_references = issues.flat_map(&:close_issue_references).compact
    GitHub::PrefillAssociations.prefill_associations(close_issue_references, :pull_request)

    pull_requests = close_issue_references.map(&:pull_request).compact
    GitHub::PrefillAssociations.prefill_associations(pull_requests, :issue) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
  end

  sig do
    override
      .params(item: MemexProjectItem)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::LinkedPullRequestsValue)
  end
  def elasticsearch_document(item)
    content_type = Elastomer::Interfaces::Document::MemexProjectItem::ContentType.deserialize(item.content_type)

    case content_type
    when Elastomer::Interfaces::Document::MemexProjectItem::ContentType::Issue
      issue = T.cast(item.content, Issue) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      issue.close_issue_references.sort_by(&:pull_request_id).map do |r|
        pull_request = T.must(r.pull_request)
        Elastomer::Interfaces::Document::LinkedPullRequests.new(
          number: pull_request.number.to_s,
          id: pull_request.id,
          repository_id: pull_request.repository_id
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
    override.
      params(
        item: MemexProjectItem,
        prefilled_associations: T.nilable(MemexProjectItem::PrefilledAssociations),
        redacted_issue_ids: T::Array[Integer],
      ).
      returns(T.nilable(T::Array[MemexProjectColumn::Interface::Serializable]))
  end
  def serializable(item, prefilled_associations: nil, redacted_issue_ids: [])
    content_type = Elastomer::Interfaces::Document::MemexProjectItem::ContentType.deserialize(item.content_type)

    case content_type
    when Elastomer::Interfaces::Document::MemexProjectItem::ContentType::Issue
      if prefilled_associations
        prefilled_associations
          .linked_pull_requests(item)
          &.reject { |pull_request| redacted_issue_ids.include?(pull_request.issue&.id) }
      else
        issue = T.cast(item.content, Issue) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        issue.close_issue_references
          .map { |r| T.must(r.pull_request) }
          .reject { |pull_request| redacted_issue_ids.include?(pull_request.issue&.id) } # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          .sort_by(&:number)
      end
    when Elastomer::Interfaces::Document::MemexProjectItem::ContentType::PullRequest,
      Elastomer::Interfaces::Document::MemexProjectItem::ContentType::DraftIssue
      nil
    else
      T.absurd(content_type)
    end
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

  sig { override.returns(String) }
  def query_by_value_path
    "field_values.#{self.class.value_name}.number"
  end

  # Returns a value that can be used to sort a MemexProjectItem by a given field.
  #
  # When querying for project items outside of ElasticSearch, this method returns the sortable value
  # for a field to regenerate the same sort order as ElasticSearch. The output for these methods should match
  # what ElasticSearch returns for the sorting order. Depending on the data type and direction, fields could
  # return the max or minimum 64-bit signed integer, a String, or a representation for Infinity.
  #
  # direction   - The direction to sort by, either :asc or :desc.
  # column_data - The data for the column to be sorted, this is JSON data stored in the column record, after
  #               extracting more specific information using the column data type to query through
  #               the MemexProjectItem::ColumnDependency::COLUMN_VALUE_KEYS Hash.
  #
  sig { override.params(direction: Symbol, column_data: T.untyped).returns(T.untyped) }
  def graphql_sortable_column_value(direction:, column_data:)
    column_data
  end
end
