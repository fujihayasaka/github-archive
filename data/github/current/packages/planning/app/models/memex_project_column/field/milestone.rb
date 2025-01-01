# typed: strict
# frozen_string_literal: true

class MemexProjectColumn::Field::Milestone < MemexProjectColumn::Field::Base
  include Interface::SpecialTypeSerializable
  include GitHub::Memoizer

  sig { override.returns(T::Array[MemexProjectItem::ContentType]) }
  def self.supported_content_types = [MemexProjectItem::ContentType::Issue, MemexProjectItem::ContentType::PullRequest]

  sig { override.returns(T::Array[String]) }
  def self.register_processors
    [
      "MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateMilestone",
      "MemexProjectColumn::Interface::Indexable::Processor::MilestoneDelete",
      "MemexProjectColumn::Interface::Indexable::Processor::MilestoneUpdate",
    ]
  end

  sig { override.returns(Elastomer::Interfaces::Mapping::FieldDataType) }
  def self.elasticsearch_mapping
    Elastomer::Interfaces::Mapping::FieldDataTypes::Object.new(properties: {
      id: Elastomer::Interfaces::Mapping::FieldDataTypes::Long.new,
      repository_id: Elastomer::Interfaces::Mapping::FieldDataTypes::Long.new,
      title: Elastomer::Interfaces::Mapping::FieldDataTypes::KeywordMultiField.new(copy_to: Elastomer::Interfaces::Mapping::MemexProjectItem::FULL_TEXT_SEARCH_FIELDS),
    })
  end

  sig { override.params(items: T::Array[MemexProjectItem]).void }
  def preload_elasticsearch_document_data(items)
    supported_items = items.reject(&:draft_issue?)

    preload_content_tree(supported_items)

    preloadable_issues = supported_items.map(&:issue).compact
    repositories = preloadable_issues.map(&:repository).compact.uniq
    GitHub::PrefillAssociations.prefill_associations(
      preloadable_issues,
      { milestone: :repository },
      available_records: repositories
    )
  end
  alias_method :preload_web_api_response_data, :preload_elasticsearch_document_data

  sig { override.params(items: T::Array[MemexProjectItem]).void }
  def preload_rest_api_response_data(items)
    preload_content_tree(items)

    pull_requests = T.cast(items.select(&:pull_request?).map(&:content).compact, T::Array[PullRequest])
    pull_request_issues = pull_requests.map(&:issue).compact
    issues = items.select(&:issue?).map(&:content).compact

    preloadable_issues = issues + pull_request_issues

    GitHub::PrefillAssociations.prefill_associations(
      preloadable_issues.compact,
      { milestone: :repository },
      available_records: items.map(&:repository)
    )
  end

  sig do
    override
      .params(item: MemexProjectItem)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::MilestoneValue)
  end
  def elasticsearch_document(item)
    content_type = MemexProjectItem::ContentType.deserialize(item.content_type)

    case content_type
    when MemexProjectItem::ContentType::Issue,
        MemexProjectItem::ContentType::PullRequest
      issue_or_pull = T.cast(item.content, T.any(Issue, PullRequest)) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      return nil unless (milestone = issue_or_pull.milestone)
      Elastomer::Interfaces::Document::Milestone.new(
        title: milestone.title,
        repository_id: item.repository_id,
        id: milestone.id
      )
    when MemexProjectItem::ContentType::DraftIssue
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
      sort_by: "field_values.#{self.class.value_name}.title.keyword",
    )
  end

  sig { override.returns(T::Hash[T.untyped, T.untyped]) }
  def existence_fragment
    {
      nested: {
        path: "field_values",
        query: {
          exists: {
            field: "field_values.#{self.class.value_name}.title"
          }
        }
      }
    }
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
    when MemexProjectItem::ContentType::Issue,
        MemexProjectItem::ContentType::PullRequest
      if prefilled_associations
        prefilled_associations.milestone(item)
      else
        issue_or_pull = T.cast(item.content, T.any(Issue, PullRequest)) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        issue_or_pull.milestone
      end
    when MemexProjectItem::ContentType::DraftIssue
      nil
    else
      T.absurd(content_type)
    end
  end

  sig { override.returns(String) }
  def group_by_value_path
    "field_values.#{self.class.value_name}.title.keyword"
  end
  [:chart_by_value_path, :slice_by_value_path].each { |method| alias_method method, :group_by_value_path }

  sig { override.returns(String) }
  def query_by_value_path
    "field_values.#{self.class.value_name}.title.lowercased_keyword"
  end

  sig { override.returns(T::Boolean) }
  def has_group_metadata? = true

  sig { override.returns(String) }
  def metadata_id_path
    "field_values.#{self.class.value_name}.id"
  end

  sig do
    override
      .params(metadata_object_ids: T::Array[Integer])
      .returns(T::Hash[Integer, T.all(Milestone, IDataSource)])
  end
  def preload_metadata_objects(metadata_object_ids)
    ::Milestone.where(id: metadata_object_ids).index_by(&:id)
  end

  sig { override.returns(T::Boolean) }
  def self.writeable? = true

  sig do
    override
    .params(
      item: MemexProjectItem,
      new_value: T.untyped,
      actor: User,

      # This parameter is required by the abstract interface, but it is not and should not be used in this method
      # because we are not at liberty to suppress Hydro events for milestones (they are part of the Issues service
      # rather than the Projects service; this method is just a convenience for interacting with milestones from
      # within Projects).
      suppress_hydro_events: T::Boolean)
    .returns(Interface::Writeable::PartialResult)
  end
  private def update_mysql_field_value(item:, new_value:, actor:, suppress_hydro_events:)
    issue = item.issue_for_content
    unless issue
      return Interface::Writeable::PartialResult.failure("Content issue not found")
    end

    canonical_write_successful = if new_value.present?
      repository = T.must(issue.repository)
      milestone = repository.milestones.find_by(id: new_value)
      unless milestone
        return Interface::Writeable::PartialResult.failure("Milestone does not exist")
      end
      issue.update(milestone:) # domain-isolation-query-violation:ignore:packages/issues (UPDATE)
    else
      issue.update(milestone_id: nil) # domain-isolation-query-violation:ignore:packages/issues (UPDATE)
    end

    unless canonical_write_successful
      return Interface::Writeable::PartialResult.failure(issue.errors.full_messages.to_sentence)
    end

    Interface::Writeable::PartialResult.success
  end

  sig { override.returns(T::Boolean) }
  def self.rest_api_serializable? = true

  sig do
    override.
     params(
       item: MemexProjectItem,
       redacted_issue_ids: T::Array[Integer],
     ).
     returns(T.nilable(T::Hash[String, T.untyped]))
  end
  def to_rest_api_hash(item, redacted_issue_ids: [])
    return unless milestone = serializable(item, redacted_issue_ids:)

    Api::Serializer.serialize(:milestone_hash, T.cast(milestone, Milestone))
  end
end
