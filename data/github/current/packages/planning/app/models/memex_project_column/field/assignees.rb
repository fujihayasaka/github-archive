# typed: strict
# frozen_string_literal: true

class MemexProjectColumn::Field::Assignees < MemexProjectColumn::Field::Base
  include Interface::SpecialTypeSerializable
  include MemexProjectColumn::Helper::Macro

  sig { override.returns(T::Array[String]) }
  def self.register_processors
    [
      "MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateAssignee",
      "MemexProjectColumn::Interface::Indexable::Processor::AccountRename",
      "MemexProjectColumn::Interface::Indexable::Processor::UserDestroy",
    ]
  end

  sig { override.returns(Elastomer::Interfaces::Mapping::FieldDataType) }
  def self.elasticsearch_mapping
    Elastomer::Interfaces::Mapping::FieldDataTypes::Object.new(properties: {
      id: Elastomer::Interfaces::Mapping::FieldDataTypes::Long.new,
      login: Elastomer::Interfaces::Mapping::FieldDataTypes::KeywordMultiField.new(copy_to: Elastomer::Interfaces::Mapping::MemexProjectItem::FULL_TEXT_SEARCH_FIELDS)
    })
  end

  sig { override.params(items: T::Array[MemexProjectItem]).void }
  def preload_elasticsearch_document_data(items)
    preload_content_tree(items)

    normal_issues = T.cast(items.select(&:issue?).map(&:content).compact, T::Array[Issue])
    pull_requests = T.cast(items.select(&:pull_request?).map(&:content).compact, T::Array[PullRequest])
    pull_request_issues = pull_requests.map(&:issue).compact
    draft_issues = T.cast(items.select(&:draft_issue?).map(&:content).compact, T::Array[DraftIssue])

    GitHub::PrefillAssociations.prefill_associations(normal_issues + pull_request_issues, :assignees)
    GitHub::PrefillAssociations.prefill_associations(draft_issues, :assignees)
  end

  alias_method :preload_web_api_response_data, :preload_elasticsearch_document_data
  alias_method :preload_rest_api_response_data, :preload_elasticsearch_document_data

  sig do
    override
      .params(item: MemexProjectItem)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::AssigneesValue)
  end
  def elasticsearch_document(item)
    content_type = MemexProjectItem::ContentType.deserialize(item.content_type)

    case content_type
    when MemexProjectItem::ContentType::Issue,
        MemexProjectItem::ContentType::DraftIssue,
        MemexProjectItem::ContentType::PullRequest
      T.must(item.content).assignees.sort_by(&:id).map do |assignee| # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        Elastomer::Interfaces::Document::Assignee.new(
          id: assignee.id,
          display_login: assignee.display_login
        )
      end
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
      returns(T::Array[T.all(User, MemexProjectColumn::IDataSource)])
  end
  def serializable(item, prefilled_associations: nil, redacted_issue_ids: [])
    if prefilled_associations
      prefilled_associations.assignees(item)
    else
      T.must(item.content).assignees.sort_by { |i| i.display_login&.downcase } # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end
  end

  sig do
    override
    .params(
      item: MemexProjectItem,
      prefilled_associations: T.nilable(MemexProjectItem::PrefilledAssociations),
      redacted_issue_ids: T::Array[Integer]
    ).returns(T.nilable(String))
  end
  def string_value(item, prefilled_associations: nil, redacted_issue_ids: [])
    values = T.cast(value(item, prefilled_associations:, redacted_issue_ids:), T::Array[MemexProjectColumnValue::SerializableValue])
    return if values.blank?

    logins = values.map(&:to_s).uniq.sort
    logins.join(", ")
  end

  sig { override.returns(Symbol) }
  def query_slug
    :assignee
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
    super(value: resolve_me_macro(value:, context:), context:)
  end

  sig { override.returns(T::Hash[T.untyped, T.untyped]) }
  def existence_fragment
    {
      nested: {
        path: "field_values",
        query: {
          exists: {
            field: "field_values.#{self.class.value_name}.login"
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
      sort_by: "field_values.#{self.class.value_name}.login.lowercased_keyword"
    )
  end

  sig { override.returns(String) }
  def chart_by_value_path
    # This method intentionally returns the plain `.keyword` path rather than the `.lowercase_keyword` path used by
    # similar methods in this class. This is because, for improved efficiency, the charting code does not retrieve
    # metadata for charting data from MySQL. Rather it uses the value stored in Elasticsearch directly.
    # This means that we must use the `.keyword` path in order to preserve and display the correct casing for each
    # assignee's handle.
    "field_values.#{self.class.value_name}.login.keyword"
  end

  sig { override.returns(String) }
  def query_by_value_path
    "field_values.#{self.class.value_name}.login.lowercased_keyword"
  end

  sig { override.returns(String) }
  def group_by_value_path
    "field_values.#{self.class.value_name}.login.lowercased_keyword"
  end
  alias_method :slice_by_value_path, :group_by_value_path

  sig { override.returns(T::Boolean) }
  def has_group_metadata? = true

  sig { override.returns(String) }
  def metadata_id_path
    "field_values.#{self.class.value_name}.id"
  end

  sig do
    override
      .params(metadata_object_ids: T::Array[Integer])
      .returns(T::Hash[Integer, T.all(User, IDataSource)])
  end
  def preload_metadata_objects(metadata_object_ids)
    User.where(id: metadata_object_ids).index_by(&:id)
  end

  sig { override.params(group_by_value: T.nilable(String)).returns(T.nilable(T::Array[String])) }
  def graphql_value(group_by_value)
    # Calling super helps cleanse potential _noValue values
    Array(super(group_by_value)).presence
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
      # because we are not at liberty to suppress Hydro events for assignees (they are part of the Issues service
      # rather than the Projects service; this method is just a convenience for interacting with assignees from
      # within Projects).
      suppress_hydro_events: T::Boolean)
    .returns(Interface::Writeable::PartialResult)
  end
  private def update_mysql_field_value(item:, new_value:, actor:, suppress_hydro_events:)
    content = item.content # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    target = content.is_a?(DraftIssue) ? content : item.issue_for_content
    unless target
      return Interface::Writeable::PartialResult.failure("Item does not support assignment.")
    end

    assignee_ids = new_value
    assignees = User.where(id: assignee_ids).to_a

    begin
      target.assignees = assignees # domain-isolation-query-violation:ignore:packages/issues (UPDATE)
    rescue ActiveRecord::RecordInvalid => e
      return Interface::Writeable::PartialResult.failure(e.message)
    end

    if target.errors[:assignees].present? || !target.save # domain-isolation-query-violation:ignore:packages/issues (UPDATE)
      assignee_logins = assignees.map(&:display_login).to_sentence
      return Interface::Writeable::PartialResult.failure("Could not be assigned to #{assignee_logins}.")
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
     returns(T.nilable(T::Array[T::Hash[String, T.untyped]]))
  end
  def to_rest_api_hash(item, redacted_issue_ids: [])
    assignees = serializable(item, redacted_issue_ids:)

    assignees.map do |assignee|
      Api::Serializer.serialize(:simple_user_hash, assignee)
    end
  end
end
