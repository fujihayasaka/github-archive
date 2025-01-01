# typed: true
# frozen_string_literal: true

require "hydro/schemas/github/event_payload_attachment/v0/issue_comment_attachment_pb"
require "hydro/schemas/github/event_payload_attachment/v0/entities/issue_comment_pb"

class Events::IssueCommentPublisher
  sig do
    params(
      issue_comment: IssueComment,
      guid: String
    ).returns(T.nilable(Events::Tier1Event))
  end
  def self.generate_deleted_tier1_event(
    issue_comment:,
    guid:
  )
    repository = issue_comment.repository
    return unless repository && issue_comment.issue

    actor = issue_comment.modifying_user
    issue = issue_comment.issue

    events_domain = Events::Domain.new

    metadata = Events::Metadata.new(
      github_request_id: GitHub.context[:request_id],
      otel_trace_id: GitHub.current_span.context.hex_trace_id,
      disabled_for_import: events_domain.model_importing?(repository),
      spammy_user_acting_outside_own_repos: actor&.spammy? || issue_comment.spammy?
    )

    actor_graphql_ids = events_domain.graphql_ids(actor)

    actor = Events::Entity.new(
      type: :ENTITY_TYPE_USER,
      id: actor.id.to_s,
      graphql_global_relay_id: actor_graphql_ids.global_relay_id,
      graphql_next_global_id: actor_graphql_ids.next_global_id,
    )

    issue_comment_graphql_ids = events_domain.graphql_ids(issue_comment)

    primary_entity = Events::Entity.new(
      type: :ENTITY_TYPE_ISSUE_COMMENT,
      id: issue_comment.id.to_s,
      graphql_global_relay_id: issue_comment_graphql_ids.global_relay_id,
      graphql_next_global_id: issue_comment_graphql_ids.next_global_id,
    )

    related_entities = []

    repository_graphql_ids = events_domain.graphql_ids(repository)
    repository_entity = Events::Entity.new(
      type: :ENTITY_TYPE_REPOSITORY,
      id: repository.id.to_s,
      graphql_global_relay_id: repository_graphql_ids.global_relay_id,
      graphql_next_global_id: repository_graphql_ids.next_global_id,
    )
    related_entities << repository_entity

    issue_graphql_ids = events_domain.graphql_ids(issue)
    issue_entity = Events::Entity.new(
      type: :ENTITY_TYPE_ISSUE,
      id: T.must(issue).id.to_s,
      graphql_global_relay_id: issue_graphql_ids.global_relay_id,
      graphql_next_global_id: issue_graphql_ids.next_global_id,
    )
    related_entities << issue_entity

    target = Events::Target.new(
      primary_entity: primary_entity,
      related_entities: related_entities,
    )

    reactions_count = issue_comment.reactions_count.map do |content, count|
      Hydro::Schemas::Github::EventPayloadAttachment::V0::Entities::IssueCommentReactionsCount.new({
        content: content,
        count: count
      })
    end

    attachment = Hydro::Schemas::Github::EventPayloadAttachment::V0::IssueCommentAttachment.new({
      issue_comment: Hydro::Schemas::Github::EventPayloadAttachment::V0::Entities::IssueComment.new({
        id: issue_comment.id,
        issue_id: issue_comment.issue_id,
        user_id: Events::ProtobufsHelper.wrap_value(Google::Protobuf::Int64Value, issue_comment.user_id),
        created_at: Events::ProtobufsHelper.wrap_timestamp(issue_comment.created_at),
        updated_at: Events::ProtobufsHelper.wrap_timestamp(issue_comment.updated_at),
        repository_id: issue_comment.repository_id,
        formatter: Events::ProtobufsHelper.wrap_value(Google::Protobuf::StringValue, issue_comment.formatter&.to_s),
        user_hidden: issue_comment.user_hidden,
        performed_by_integration_id: Events::ProtobufsHelper.wrap_value(Google::Protobuf::Int64Value, issue_comment.performed_by_integration_id),
        comment_hidden: issue_comment.comment_hidden ? 1 : 0,
        comment_hidden_reason: Events::ProtobufsHelper.wrap_value(Google::Protobuf::StringValue, issue_comment.comment_hidden_reason),
        comment_hidden_classifier: Events::ProtobufsHelper.wrap_value(Google::Protobuf::StringValue, issue_comment.comment_hidden_classifier),
        # comment_hidden_by is stored as an integer, but calling the model method returns a string enum value so we read it without casting.
        comment_hidden_by: Events::ProtobufsHelper.wrap_value(Google::Protobuf::Int32Value, issue_comment.read_attribute_before_type_cast(:comment_hidden_by)),
        # compressed body is stored as a byte array, but calling the model method returns a string so we read it without casting.
        compressed_body: Events::ProtobufsHelper.wrap_value(Google::Protobuf::BytesValue, issue_comment.read_attribute_before_type_cast(:compressed_body)&.to_s&.b),
      }),
      issue_comment_reactions_count: reactions_count
    })

    event_attachment = Events::EventAttachment.new(
      type_url: "type.googleapis.com/hydro.schemas.github.event_payload_attachment.v0.IssueCommentAttachment",
      message: T.unsafe(Hydro::Schemas::Github::EventPayloadAttachment::V0::IssueCommentAttachment).encode(attachment)
    )

    Events::Tier1Event.new(
      type: :EVENT_TYPE_ISSUE_COMMENT,
      action: :EVENT_ACTION_DELETED,
      target: target,
      actor: actor,
      metadata: metadata,
      guid: guid,
      target_repository_id: repository.id,
      target_organization_id: repository.organization_id,
      target_business_id: repository.organization&.business&.id,
      event_attachment: event_attachment
    )
  end

  sig { params(tier1_event: Events::Tier1Event, event_flags: Events::Tier1EventPublisher::EventFlags).void }
  def self.publish(tier1_event:, event_flags:)
    Events::Tier1EventPublisher.publish(tier1_event, topic: "events_platform.v0.IssueComment", event_flags: event_flags)
  end
end
