# typed: true
# frozen_string_literal: true

require "hydro/schemas/github/event_payload_attachment/v0/issue_attachment_pb"
require "hydro/schemas/github/event_payload_attachment/v0/entities/issue_pb"

class Events::IssuesPublisher
  sig do
    params(
      actor: User,
      repository: Repository,
      issue: Issue,
      event_flags: Events::Tier1EventPublisher::EventFlags,
      guid: T.nilable(String)
    ).void
  end
  def self.opened(actor:,
    repository:,
    issue:,
    event_flags:,
    guid: nil
  )
    metadata = get_metadata(repository: repository, actor: actor, issue: issue)

    actor = get_actor(actor: actor)

    graphql_ids = Events::Domain.new.graphql_ids(issue: issue)

    primary_entity = get_primary_entity(issue: issue)

    related_entity = get_related_entity(repository: repository)

    target = get_target(primary_entity: primary_entity, related_entity: related_entity)

    event = Events::Tier1Event.new(
      type: :EVENT_TYPE_ISSUES,
      action: :EVENT_ACTION_OPENED,
      target: target,
      actor: actor,
      metadata: metadata,
      guid: guid,
      target_repository_id: repository.id,
      target_organization_id: repository.organization_id,
      target_business_id: repository.organization&.business&.id,
      event_attachment: nil,
    )

    self.publish_tier1_event(tier1_event: event, event_flags: event_flags)
  end

  sig do
    params(
      actor: User,
      repository: T.nilable(Repository),
      issue: Issue,
      guid: T.nilable(String)
    ).returns(T.nilable(Events::Tier1Event))
  end
  def self.generate_deleted_tier1_event(actor:,
    repository:,
    issue:,
    guid: nil
  )
    return unless repository
    metadata = get_metadata(repository: repository, actor: actor, issue: issue)

    actor = get_actor(actor: actor)

    primary_entity = get_primary_entity(issue: issue)

    related_entity = get_related_entity(repository: repository)

    target = get_target(primary_entity: primary_entity, related_entity: related_entity)

    issue = Hydro::Schemas::Github::EventPayloadAttachment::V0::Entities::Issue.new(
      id: issue.id,
      repository_id: repository.id,
      user_id: Events::ProtobufsHelper.wrap_value(Google::Protobuf::Int64Value, issue.user_id),
      issue_comments_count: issue.issue_comments_count,
      number: issue.number,
      position: issue.position,
      title: Events::ProtobufsHelper.wrap_value(Google::Protobuf::BytesValue, issue.read_attribute_before_type_cast(:title).to_s),
      state: get_issue_state(state: issue.state),
      created_at: Events::ProtobufsHelper.wrap_timestamp(issue.created_at),
      updated_at: Events::ProtobufsHelper.wrap_timestamp(issue.updated_at),
      closed_at: Events::ProtobufsHelper.wrap_timestamp(issue.closed_at),
      pull_request_id: Events::ProtobufsHelper.wrap_value(Google::Protobuf::Int64Value, issue.pull_request_id),
      milestone_id: Events::ProtobufsHelper.wrap_value(Google::Protobuf::Int64Value, issue.milestone_id),
      assignee_id: Events::ProtobufsHelper.wrap_value(Google::Protobuf::Int64Value, issue.assignee_id),
      contributed_at_timestamp: Events::ProtobufsHelper.wrap_value(Google::Protobuf::Int64Value, issue.contributed_at_timestamp),
      contributed_at_offset: Events::ProtobufsHelper.wrap_value(Google::Protobuf::Int32Value, issue.contributed_at_offset),
      user_hidden: issue.user_hidden,
      performed_by_integration_id: Events::ProtobufsHelper.wrap_value(Google::Protobuf::Int64Value, issue.performed_by_integration_id),
      has_pull_request: issue.has_pull_request,
      locked_at: Events::ProtobufsHelper.wrap_timestamp(issue.locked_at),
      compressed_body: Events::ProtobufsHelper.wrap_value(Google::Protobuf::BytesValue, issue.read_attribute_before_type_cast(:compressed_body)&.to_s&.b),
      issue_type_id: Events::ProtobufsHelper.wrap_value(Google::Protobuf::Int64Value, issue.issue_type_id),
      issue_state_reason: Events::ProtobufsHelper.wrap_value(Google::Protobuf::StringValue, issue.state_reason),
    )

    issue_attachment = Hydro::Schemas::Github::EventPayloadAttachment::V0::IssueAttachment.new(issue: issue)

    event_attachment = Events::EventAttachment.new(
      type_url: "type.googleapis.com/hydro.schemas.github.event_payload_attachment.v0.IssueAttachment",
      message: T.unsafe(Hydro::Schemas::Github::EventPayloadAttachment::V0::IssueAttachment).encode(issue_attachment)
    )

    Events::Tier1Event.new(
      guid: guid,
      type: :EVENT_TYPE_ISSUES,
      action: :EVENT_ACTION_DELETED,
      target: target,
      actor: actor,
      metadata: metadata,
      target_repository_id: repository.id,
      target_organization_id: repository.organization_id,
      target_business_id: repository.organization&.business&.id,
      event_attachment: event_attachment
    )
  end

  sig do
    params(
      repository: T.nilable(Repositories::IRepository),
      actor: T.nilable(User),
      issue: T.nilable(Issue)
    ).returns(Events::Metadata)
  end
  def self.get_metadata(
    repository:,
    actor:,
    issue:
  )
    metadata = Events::Metadata.new(
      github_request_id: GitHub.context[:request_id],
      otel_trace_id: GitHub.current_span.context.hex_trace_id,
      disabled_for_import: Events::Domain.new.model_importing?(repository),
      spammy_user_acting_outside_own_repos: actor.try(:spammy?) || (issue && issue.user.try(:spammy?))
    )
  end

  sig { params(actor: User).returns(Events::Entity) }
  def self.get_actor(actor:)
    actor_graphql_ids = Events::Domain.new.graphql_ids(actor)

    actor = Events::Entity.new(
      type: :ENTITY_TYPE_USER,
      id: actor.id.to_s,
      graphql_global_relay_id: actor_graphql_ids.global_relay_id,
      graphql_next_global_id: actor_graphql_ids.next_global_id,
    )
  end

  sig { params(issue: Issue).returns(Events::Entity) }
  def self.get_primary_entity(issue:)
    graphql_ids = Events::Domain.new.graphql_ids(issue)

    primary_entity = Events::Entity.new(
      type: :ENTITY_TYPE_ISSUE,
      id: issue.id.to_s,
      graphql_global_relay_id: graphql_ids.global_relay_id,
      graphql_next_global_id: graphql_ids.next_global_id,
    )
  end

  sig { params(repository: Repository).returns(Events::Entity) }
  def self.get_related_entity(repository:)
    repository_graphql_ids = Events::Domain.new.graphql_ids(repository)

    related_entity = Events::Entity.new(
      type: :ENTITY_TYPE_REPOSITORY,
      id: repository.id.to_s,
      graphql_global_relay_id: repository_graphql_ids.global_relay_id,
      graphql_next_global_id: repository_graphql_ids.next_global_id,
    )
  end

  sig { params(primary_entity: Events::Entity, related_entity: Events::Entity).returns(Events::Target) }
  def self.get_target(
    primary_entity:,
    related_entity:
  )
    target = Events::Target.new(
      primary_entity: primary_entity,
      related_entities: [related_entity],
    )
  end

  sig { params(state: T.nilable(String)).returns(Symbol) }
  def self.get_issue_state(state:)
    case state
    when "open"
      return :OPEN
    when "closed"
      return :CLOSED
    end
    :ISSUE_STATE_UNKNOWN
  end

  sig { params(tier1_event: T.nilable(Events::Tier1Event), event_flags: Events::Tier1EventPublisher::EventFlags).void }
  def self.publish_tier1_event(tier1_event:, event_flags:)
    Events::Tier1EventPublisher.publish(tier1_event, topic: "events_platform.v0.Issues", event_flags: event_flags) if tier1_event.present?
  end
end
