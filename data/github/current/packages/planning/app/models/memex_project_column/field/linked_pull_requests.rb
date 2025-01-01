# typed: strict
# frozen_string_literal: true

class MemexProjectColumn::Field::LinkedPullRequests < MemexProjectColumn::Field::Base
  include Interface::SpecialTypeSerializable

  sig { override.returns(T::Array[MemexProjectItem::ContentType]) }
  def self.supported_content_types = [MemexProjectItem::ContentType::Issue]

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
    supported_items = items.select(&:issue?)

    preload_content_tree(supported_items)

    issues = supported_items.map(&:issue).compact
    repositories = issues.map(&:repository).compact.uniq
    GitHub::PrefillAssociations.prefill_associations(issues, :close_issue_references)

    close_issue_references = issues.flat_map(&:close_issue_references).compact
    GitHub::PrefillAssociations.prefill_associations( # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      close_issue_references,
      { pull_request: [:issue, :repository] },
      available_records: issues + repositories
    )
  end
  alias_method :preload_web_api_response_data, :preload_elasticsearch_document_data

  sig { override.params(items: T::Array[MemexProjectItem]).void }
  def preload_rest_api_response_data(items)
    preload_content_tree(items)

    issues = T.cast(items.select(&:issue?).map(&:content).compact, T::Array[Issue])
    GitHub::PrefillAssociations.prefill_associations(issues, :close_issue_references)

    close_issue_references = issues.flat_map(&:close_issue_references).compact
    GitHub::PrefillAssociations.prefill_associations(close_issue_references, :pull_request)

    pull_requests = close_issue_references.map(&:pull_request).compact

    pulls_by_repo = pull_requests.group_by(&:repository)
    pulls_by_repo.each do |repository, pulls|
      PullRequest.prefill_rest_api_list_repo_pulls(pulls, nil, mirror: true, repository: T.must(repository), issues:)
    end

    Repository.prefill_associations(pulls_by_repo.keys, internal: true)
  end

  sig do
    override
      .params(item: MemexProjectItem)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::LinkedPullRequestsValue)
  end
  def elasticsearch_document(item)
    content_type = MemexProjectItem::ContentType.deserialize(item.content_type)

    case content_type
    when MemexProjectItem::ContentType::Issue
      issue = T.cast(item.content, Issue) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      issue.close_issue_references.sort_by(&:pull_request_id).map do |r|
        pull_request = T.must(r.pull_request)
        Elastomer::Interfaces::Document::LinkedPullRequests.new(
          number: pull_request.number.to_s,
          id: pull_request.id,
          repository_id: pull_request.repository_id
        )
      end
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
      returns(T.nilable(T::Array[MemexProjectColumn::IDataSource]))
  end
  def serializable(item, prefilled_associations: nil, redacted_issue_ids: [])
    content_type = MemexProjectItem::ContentType.deserialize(item.content_type)

    case content_type
    when MemexProjectItem::ContentType::Issue
      if prefilled_associations
        prefilled_associations
          .linked_pull_requests(item)
          .reject { |pull_request| redacted_issue_ids.include?(pull_request.issue&.id) }
      else
        issue = T.cast(item.content, Issue) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        issue.close_issue_references
          .map { |r| T.must(r.pull_request) }
          .reject { |pull_request| redacted_issue_ids.include?(pull_request.issue&.id) } # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          .sort_by(&:number)
      end
    when MemexProjectItem::ContentType::PullRequest,
      MemexProjectItem::ContentType::DraftIssue
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

  sig { override.returns(T::Boolean) }
  def self.rest_api_serializable? = true

  sig do
    override.
     params(
       item: MemexProjectItem,
       redacted_issue_ids: T::Array[Integer],
     ).
     returns(T.nilable(T::Array[T::Hash[String, T.untyped]]))
  end
  def to_rest_api_hash(item, redacted_issue_ids: [])
    return unless pull_requests = T.cast(serializable(item, redacted_issue_ids:), T.nilable(T::Array[PullRequest]))

    pull_requests.map do |pull_request|
      Api::Serializer.serialize(:pull_request_hash, pull_request, { repo_identifier_only: true })
    end
  end
end
