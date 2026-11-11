# typed: strict
# frozen_string_literal: true

class MemexProjectColumn::Field::Assignees < MemexProjectColumn::Field::Base
  include Interface::SpecialTypeSerializable
  include MemexProjectColumn::Helper::Macro
  include CopilotHelper

  sig { override.returns(T::Array[MemexProjectItem::ContentType]) }
  def self.supported_content_types = [
    MemexProjectItem::ContentType::Issue,
    MemexProjectItem::ContentType::PullRequest,
    MemexProjectItem::ContentType::DraftIssue,
  ]

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

  sig { override.params(items: T::Array[MemexProjectItem], opts: RestApiPreloadOptions).void }
  def preload_rest_api_response_data(items, opts = RestApiPreloadOptions.new)
    # Preload configuration for the memex owner if necessary
    should_preload_profiles?(items)

    normal_issues = T.cast(items.select(&:issue?).map(&:content).compact, T::Array[Issue]) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    pull_requests = T.cast(items.select(&:pull_request?).map(&:content).compact, T::Array[PullRequest])
    pull_request_issues = pull_requests.map(&:issue).compact
    draft_issues = T.cast(items.select(&:draft_issue?).map(&:content).compact, T::Array[DraftIssue])

    GitHub::PrefillAssociations.prefill_associations(normal_issues + pull_request_issues, :assignees)
    GitHub::PrefillAssociations.prefill_associations(draft_issues, :assignees)
  end

  sig do
    override
      .params(items: T::Array[MemexProjectItem], fields: T::Array[MemexProjectColumn::Field::Base])
      .returns(T.nilable(T::Hash[Integer, T.untyped]))
  end
  private def preload_web_api_response_data(items:, fields:)
    preload_relations = should_preload_profiles?(items) ? { assignee: :profile } : :assignee

    assignments_by_issue_id = Assignment
      .select(:issue_id, :assignee_id)
      .includes(preload_relations)
      .where(issue_id: items.map(&:issue_id).compact)
      .group_by(&:issue_id)

    assignments_by_draft_issue_id = DraftIssueAssignment
      .select(:target_id, :assignee_id)
      .includes(preload_relations)
      .where(target_type: DraftIssue.name, target_id: items.select(&:draft_issue?).map(&:content_id))
      .group_by(&:target_id)

    items.each_with_object({}) do |item, result|
      assignments = if item.draft_issue?
        assignments_by_draft_issue_id.fetch(item.content_id, [])
      elsif item.issue_id
        assignments_by_issue_id.fetch(item.issue_id, [])
      else
        []
      end

      result[item.id] = assignments
        .map(&:assignee)
        .compact
        .sort_by { |user| user.display_login.downcase }
    end
  end

  sig { params(items: T::Array[MemexProjectItem]).returns(T::Boolean) }
  private def should_preload_profiles?(items)
    items.first&.memex_project&.owner_display_name_configuration_needs_profile? || false
  end

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
      T.cast(T.must(item.content), T.any(Issue, PullRequest, DraftIssue)).assignees.sort_by(&:id).map do |assignee| # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        Elastomer::Interfaces::Document::Assignee.new(
          id: assignee.id,
          login: assignee.display_login
        )
      end
    when MemexProjectItem::ContentType::AgentTask
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
      returns(T::Array[T.all(Assignee, MemexProjectColumn::IDataSource)])
  end
  def serializable(item, prefilled_associations: nil, redacted_issue_ids: [])
    include_name = should_preload_profiles?([item])

    users = if prefilled_associations
      prefilled_associations.assignees(item)
    elsif preloaded_web_api_response_data?
      preloaded_web_api_response_data[item.id]
    else
      T.cast(T.must(item.content), T.any(Issue, PullRequest, DraftIssue)).assignees.sort_by { |i| i.display_login&.downcase } # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end

    users.map { |user| Assignee.new(user, include_name:) }
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

    if target.is_a?(Issue) && FeatureFlag.vexi.enabled?(:memex_multi_agent_assignments, actor, default: false)
      return update_issue_assignees_with_orchestration(issue: target, assignees:, actor:)
    else
      begin
        target.assignees = assignees # domain-isolation-query-violation:ignore:packages/issues (UPDATE)
      rescue ActiveRecord::RecordInvalid => e
        return Interface::Writeable::PartialResult.failure(e.message)
      end
    end

    if target.errors[:assignees].present? || !target.save # domain-isolation-query-violation:ignore:packages/issues (UPDATE)
      return set_errors(assignees)
    end

    Interface::Writeable::PartialResult.success
  end

  # Updates issue assignees through the Issues domain to trigger orchestration for agent sessions.
  # Don't call this method from inside an open transaction
  # Ref: https://github.com/github/github/blob/master/packages/issues/app/public/issues/domain.rb#L552-L561
  sig { params(issue: Issue, assignees: T::Array[User], actor: User).returns(Interface::Writeable::PartialResult) }
  private def update_issue_assignees_with_orchestration(issue:, assignees:, actor:)
    return set_errors(assignees) if invalid_assignment?(issue:, assignees:, actor:)

    update_attributes = Issues::UpdateIssueAttributes.new(
      assignees: Issues::UpdateIssueAttribute::Set.new(assignees),
    )

    copilot_context = build_copilot_context_for_agent_assignees(issue:, assignees:, actor:)
    result = Issues.domain.update(issue, update_attributes, actor, copilot_context:)

    if result.ok?
      Interface::Writeable::PartialResult.success
    else
      Interface::Writeable::PartialResult.failure(result.error&.message || "Failed to update assignees")
    end
  rescue ActiveRecord::RecordInvalid => e
    Interface::Writeable::PartialResult.failure(e.message)
  end

  # Builds a copilot_context if any of the assignees are agent bots
  sig { params(issue: Issue, assignees: T::Array[User], actor: User).returns(IssueOrchestration::CopilotContext) }
  private def build_copilot_context_for_agent_assignees(issue:, assignees:, actor:)
    new_agent_assignees = find_new_agent_assignees(issue, assignees)
    return nil unless new_agent_assignees

    {
      request_token: build_copilot_api_token(actor).to_s,
      attributes: build_assignment_attributes(issue),
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
     returns(T.nilable(T::Array[T::Hash[String, T.untyped]]))
  end
  def to_rest_api_hash(item, redacted_issue_ids: [])
    assignees = serializable(item, redacted_issue_ids:)

    assignees.map do |assignee|
      Api::Serializer.serialize(:simple_user_hash, assignee.user)
    end
  end

  private

  # Returns true if any assignees are invalid for issue or actor doesn't have permission to assign them
  # Issue#assignees filters out invalid assignees
  sig { params(issue: Issue, assignees: T::Array[User], actor: User).returns(T::Boolean) }
  def invalid_assignment?(issue:, assignees:, actor:)
    actor_cannot_assign_to_issue?(issue, actor) || any_assignees_invalid?(issue, assignees)
  end

  sig { params(assignees: T::Array[User]).returns(MemexProjectColumn::Interface::Writeable::PartialResult) }
  def set_errors(assignees)
    assignee_logins = assignees.map(&:display_login).to_sentence
    Interface::Writeable::PartialResult.failure("Could not be assigned to #{assignee_logins}.")
  end

  sig { params(issue: Issue, actor: User).returns(T::Boolean) }
  def actor_cannot_assign_to_issue?(issue, actor)
    !Issues.domain.set_assignees?(issue, actor)
  end

  sig { params(issue: Issue, assignees: T::Array[User]).returns(T::Boolean) }
  def any_assignees_invalid?(issue, assignees)
    return false if assignees.empty?

    valid_assignee_ids = issue.available_assignee_ids
    assignees.any? { |user| !valid_assignee_ids.include?(user.id) }
  end

  sig { params(issue: Issue, assignees: T::Array[User]).returns(T.nilable(User)) }
  def find_new_agent_assignees(issue, assignees)
    current_assignee_ids = issue.assignees.map(&:id)

    assignees.find do |user|
      !current_assignee_ids.include?(user.id) && AgenticApp.agent_for_bot_id(user.id)
    end
  end

  sig { params(issue: Issue).returns(Issues::AgentAssignmentNewAttributes) }
  def build_assignment_attributes(issue)
    repository = issue.repository

    assignment_attributes = Issues::AgentAssignmentNewAttributes.new(
      target_repository: T.must(repository),
      base_ref: T.must(repository).default_branch
    )
  end
end
