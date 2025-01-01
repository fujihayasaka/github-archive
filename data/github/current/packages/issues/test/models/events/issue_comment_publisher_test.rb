# typed: true
# frozen_string_literal: true

require "test_helper"
require "hydro/schemas/github/event_payload_attachment/v0/issue_comment_attachment_pb"
require "hydro/schemas/github/event_payload_attachment/v0/entities/issue_comment_pb"
require "hydro/schemas/github/event_payload_attachment/v0/entities/issue_comment_reactions_count_pb"

class Events::IssueCommentPublisherTest < GitHub::TestCase
  fixtures do
    @actor = create(:user)
    @repository = create(:public_repository, owner: @actor)
    @issue = create :issue, :with_instrumentation, :wait_for_orchestration, user: @actor, title: "Hello", body: "World", repository: @repository
    @mock_guid = "9dd711f0-54bb-11ef-8bdf-5708d685333a"
    @comment = create :issue_comment, issue: @issue, user: @author, comment_hidden_by: GitHub::MinimizeComment::ROLES[:minimized_by_maintainer], performed_by_integration_id: 123, comment_hidden_reason: "spam", comment_hidden_classifier: "spam"
  end

  test "does not generate issue comment deleted event when feature flag enabled" do
    GitHub.flipper[:events_v2_publish_issue_comment_deleted_tier1_event].disable
    tier1_event = Events::IssueCommentPublisher.generate_deleted_tier1_event(
      issue_comment: @comment,
      guid: @mock_guid
    )
    assert_nil tier1_event
  end

  test "does not generate issue comment deleted event when issue or repository do not exist" do
    GitHub.flipper[:events_v2_publish_issue_comment_deleted_tier1_event].enable

    comment_without_issue = create :issue_comment, issue: nil, user: @author
    comment_without_issue.issue.destroy!
    comment_without_issue.reload
    tier1_event = Events::IssueCommentPublisher.generate_deleted_tier1_event(
      issue_comment: comment_without_issue,
      guid: @mock_guid
    )
    assert_nil tier1_event

    issue = create :issue, :with_instrumentation, :wait_for_orchestration, user: @actor, title: "Hello", body: "World"
    comment_without_repository = create :issue_comment, issue: issue, user: @author
    comment_without_repository.repository.destroy!
    comment_without_repository.reload
    tier1_event = Events::IssueCommentPublisher.generate_deleted_tier1_event(
      issue_comment: comment_without_repository,
      guid: @mock_guid
    )
    assert_nil tier1_event
  end

  test "generates issue comment deleted tier 1 event when feature flag enabled" do
    GitHub.flipper[:events_v2_publish_issue_comment_deleted_tier1_event].enable(@repository)
    now = Time.now
    Timecop.freeze(now) do
      IssueCommentReaction.react(
        user: @comment.user,
        subject_id: @comment.id,
        content: "tada"
      )
      reactions_count = [
        Hydro::Schemas::Github::EventPayloadAttachment::V0::Entities::IssueCommentReactionsCount.new({
          content: "tada",
          count: 1
        })
      ]
      expected_attachment = Hydro::Schemas::Github::EventPayloadAttachment::V0::IssueCommentAttachment.new({
        issue_comment: Hydro::Schemas::Github::EventPayloadAttachment::V0::Entities::IssueComment.new({
          id: @comment.id,
          issue_id: @comment.issue_id,
          user_id: Google::Protobuf::Int64Value.new(value: @comment.user_id),
          created_at: Google::Protobuf::Timestamp.new(seconds: @comment.created_at.to_i),
          updated_at: Google::Protobuf::Timestamp.new(seconds: @comment.updated_at.to_i),
          repository_id: @comment.repository_id,
          formatter: Google::Protobuf::StringValue.new(value: @comment.formatter.to_s),
          user_hidden: @comment.user_hidden,
          performed_by_integration_id: Google::Protobuf::Int64Value.new(value: @comment.performed_by_integration_id),
          comment_hidden: @comment.comment_hidden ? 1 : 0,
          comment_hidden_reason: Google::Protobuf::StringValue.new(value: @comment.comment_hidden_reason),
          comment_hidden_classifier: Google::Protobuf::StringValue.new(value: @comment.comment_hidden_classifier),
          comment_hidden_by: Google::Protobuf::Int32Value.new(value: @comment.read_attribute_before_type_cast(:comment_hidden_by)),
          compressed_body: Google::Protobuf::BytesValue.new(value: @comment.read_attribute_before_type_cast(:compressed_body)&.to_s)
          }),
          issue_comment_reactions_count: reactions_count
      })

      expected_attachment_value = Events::EventAttachment.new(
        type_url: "type.googleapis.com/hydro.schemas.github.event_payload_attachment.v0.IssueCommentAttachment",
        message: T.unsafe(Hydro::Schemas::Github::EventPayloadAttachment::V0::IssueCommentAttachment).encode(expected_attachment)
      )

      expected_tier1_event = Events::Tier1Event.new(
        type: :EVENT_TYPE_ISSUE_COMMENT,
        action: :EVENT_ACTION_DELETED,
        guid: @mock_guid,
        target: Events::Target.new(
          primary_entity: Events::Entity.new(
            type: :ENTITY_TYPE_ISSUE_COMMENT,
            id: @comment.id.to_s,
            graphql_global_relay_id: @comment.global_relay_id,
            graphql_next_global_id: @comment.next_global_id,
          ),
          related_entities: [Events::Entity.new(
            type: :ENTITY_TYPE_REPOSITORY,
            id: @repository.id.to_s,
            graphql_global_relay_id: @repository.global_relay_id,
            graphql_next_global_id: @repository.next_global_id,
          ), Events::Entity.new(
            type: :ENTITY_TYPE_ISSUE,
            id: @issue.id.to_s,
            graphql_global_relay_id: @issue.global_relay_id,
            graphql_next_global_id: @issue.next_global_id,
          )],
        ),
        actor: Events::Entity.new(
          type: :ENTITY_TYPE_USER,
          id: @actor.id.to_s,
          graphql_global_relay_id: @actor.global_relay_id,
          graphql_next_global_id: @actor.next_global_id,
        ),
        metadata: Events::Metadata.new(
          github_request_id: GitHub.context[:request_id],
          otel_trace_id: GitHub.current_span.context.hex_trace_id,
          disabled_for_import: false
        ),
        event_attachment: expected_attachment_value,
        target_repository_id: @repository.id,
        target_organization_id: @repository.organization_id,
        target_business_id: @repository.organization&.business&.id,
      )

      tier1_event = Events::IssueCommentPublisher.generate_deleted_tier1_event(
        issue_comment: @comment,
        guid: @mock_guid
      )
      assert_equal expected_tier1_event, tier1_event
    end
  end

  test "generates issue comment deleted tier 1 event with body contains utf-8 when feature flag enabled" do
    GitHub.flipper[:events_v2_publish_issue_comment_deleted_tier1_event].enable(@repository)
    @comment.body = "König, доброе"
    now = Time.now
    Timecop.freeze(now) do
      IssueCommentReaction.react(
        user: @comment.user,
        subject_id: @comment.id,
        content: "tada"
      )
      reactions_count = [
        Hydro::Schemas::Github::EventPayloadAttachment::V0::Entities::IssueCommentReactionsCount.new({
          content: "tada",
          count: 1
        })
      ]
      expected_attachment = Hydro::Schemas::Github::EventPayloadAttachment::V0::IssueCommentAttachment.new({
        issue_comment: Hydro::Schemas::Github::EventPayloadAttachment::V0::Entities::IssueComment.new({
          id: @comment.id,
          issue_id: @comment.issue_id,
          user_id: Google::Protobuf::Int64Value.new(value: @comment.user_id),
          created_at: Google::Protobuf::Timestamp.new(seconds: @comment.created_at.to_i),
          updated_at: Google::Protobuf::Timestamp.new(seconds: @comment.updated_at.to_i),
          repository_id: @comment.repository_id,
          formatter: Google::Protobuf::StringValue.new(value: @comment.formatter.to_s),
          user_hidden: @comment.user_hidden,
          performed_by_integration_id: Google::Protobuf::Int64Value.new(value: @comment.performed_by_integration_id),
          comment_hidden: @comment.comment_hidden ? 1 : 0,
          comment_hidden_reason: Google::Protobuf::StringValue.new(value: @comment.comment_hidden_reason),
          comment_hidden_classifier: Google::Protobuf::StringValue.new(value: @comment.comment_hidden_classifier),
          comment_hidden_by: Google::Protobuf::Int32Value.new(value: @comment.read_attribute_before_type_cast(:comment_hidden_by)),
          compressed_body: Google::Protobuf::BytesValue.new(value: @comment.read_attribute_before_type_cast(:compressed_body)&.to_s.b)
          }),
          issue_comment_reactions_count: reactions_count
      })

      expected_attachment_value = Events::EventAttachment.new(
        type_url: "type.googleapis.com/hydro.schemas.github.event_payload_attachment.v0.IssueCommentAttachment",
        message: T.unsafe(Hydro::Schemas::Github::EventPayloadAttachment::V0::IssueCommentAttachment).encode(expected_attachment)
      )

      expected_tier1_event = Events::Tier1Event.new(
        type: :EVENT_TYPE_ISSUE_COMMENT,
        action: :EVENT_ACTION_DELETED,
        guid: @mock_guid,
        target: Events::Target.new(
          primary_entity: Events::Entity.new(
            type: :ENTITY_TYPE_ISSUE_COMMENT,
            id: @comment.id.to_s,
            graphql_global_relay_id: @comment.global_relay_id,
            graphql_next_global_id: @comment.next_global_id,
          ),
          related_entities: [Events::Entity.new(
            type: :ENTITY_TYPE_REPOSITORY,
            id: @repository.id.to_s,
            graphql_global_relay_id: @repository.global_relay_id,
            graphql_next_global_id: @repository.next_global_id,
          ), Events::Entity.new(
            type: :ENTITY_TYPE_ISSUE,
            id: @issue.id.to_s,
            graphql_global_relay_id: @issue.global_relay_id,
            graphql_next_global_id: @issue.next_global_id,
          )],
        ),
        actor: Events::Entity.new(
          type: :ENTITY_TYPE_USER,
          id: @actor.id.to_s,
          graphql_global_relay_id: @actor.global_relay_id,
          graphql_next_global_id: @actor.next_global_id,
        ),
        metadata: Events::Metadata.new(
          github_request_id: GitHub.context[:request_id],
          otel_trace_id: GitHub.current_span.context.hex_trace_id,
          disabled_for_import: false
        ),
        event_attachment: expected_attachment_value,
        target_repository_id: @repository.id,
        target_organization_id: @repository.organization_id,
        target_business_id: @repository.organization&.business&.id,
      )

      tier1_event = Events::IssueCommentPublisher.generate_deleted_tier1_event(
        issue_comment: @comment,
        guid: @mock_guid
      )
      assert_equal expected_tier1_event, tier1_event
    end
  end

  test "generates issue comment deleted tier 1 event with attachment when nilable values are nil" do
    GitHub.flipper[:events_v2_publish_issue_comment_deleted_tier1_event].enable(@repository)
    now = Time.now
    Timecop.freeze(now) do
      IssueCommentReaction.react(
        user: @comment.user,
        subject_id: @comment.id,
        content: "tada"
      )
      reactions_count = [
        Hydro::Schemas::Github::EventPayloadAttachment::V0::Entities::IssueCommentReactionsCount.new({
          content: "tada",
          count: 1
        })
      ]

      @comment.user_id = nil
      @comment.created_at = nil
      @comment.updated_at = nil
      @comment.formatter = nil
      @comment.performed_by_integration_id = nil
      @comment.comment_hidden_reason = nil
      @comment.comment_hidden_classifier = nil
      @comment.comment_hidden_by = nil
      @comment.compressed_body = nil
      @comment.save(validate: false)

      expected_attachment = Hydro::Schemas::Github::EventPayloadAttachment::V0::IssueCommentAttachment.new({
        issue_comment: Hydro::Schemas::Github::EventPayloadAttachment::V0::Entities::IssueComment.new({
          id: @comment.id,
          issue_id: @comment.issue_id,
          user_id: nil,
          created_at: nil,
          updated_at: nil,
          repository_id: @comment.repository_id,
          # formatter defaults to `markdown` if nil
          formatter: Google::Protobuf::StringValue.new(value: @comment.formatter.to_s),
          user_hidden: @comment.user_hidden,
          performed_by_integration_id: nil,
          comment_hidden: @comment.comment_hidden ? 1 : 0,
          comment_hidden_reason: nil,
          comment_hidden_classifier: nil,
          comment_hidden_by: nil,
          compressed_body: nil
          }),
          issue_comment_reactions_count: reactions_count
      })

      tier1_event = Events::IssueCommentPublisher.generate_deleted_tier1_event(
        issue_comment: @comment,
        guid: @mock_guid
      )

      actual_attachment = T.unsafe(Hydro::Schemas::Github::EventPayloadAttachment::V0::IssueCommentAttachment).decode(tier1_event&.event_attachment&.message)
      assert_equal expected_attachment, actual_attachment
    end
  end

  test "publishes event" do
    expected_attachment = Hydro::Schemas::Github::EventPayloadAttachment::V0::IssueCommentAttachment.new({
      issue_comment: Hydro::Schemas::Github::EventPayloadAttachment::V0::Entities::IssueComment.new({
        id: @comment.id,
        issue_id: @comment.issue_id,
        user_id: Google::Protobuf::Int64Value.new(value: @comment.user_id),
        created_at: Google::Protobuf::Timestamp.new(seconds: @comment.created_at.to_i),
        updated_at: Google::Protobuf::Timestamp.new(seconds: @comment.updated_at.to_i),
        repository_id: @comment.repository_id,
        formatter: Google::Protobuf::StringValue.new(value: @comment.formatter.to_s),
        user_hidden: @comment.user_hidden,
        performed_by_integration_id: Google::Protobuf::Int64Value.new(value: @comment.performed_by_integration_id),
        comment_hidden: @comment.comment_hidden ? 1 : 0,
        comment_hidden_reason: @comment.comment_hidden_reason ? Google::Protobuf::StringValue.new(value: @comment.comment_hidden_reason) : nil,
        comment_hidden_classifier: Google::Protobuf::StringValue.new(value: @comment.comment_hidden_classifier),
        comment_hidden_by: Google::Protobuf::Int32Value.new(value: @comment.read_attribute_before_type_cast(:comment_hidden_by)),
        compressed_body: @comment.attributes[:compressed_body],
      })
    })
    expected_attachment_value = Events::EventAttachment.new(
      type_url: "type.googleapis.com/hydro.schemas.github.event_payload_attachment.v0.IssueCommentAttachment",
      message: T.unsafe(Hydro::Schemas::Github::EventPayloadAttachment::V0::IssueCommentAttachment).encode(expected_attachment)
    )

    expected_tier1_event = Events::Tier1Event.new(
      type: :EVENT_TYPE_ISSUE_COMMENT,
      action: :EVENT_ACTION_DELETED,
      guid: @mock_guid,
      target: Events::Target.new(
        primary_entity: Events::Entity.new(
          type: :ENTITY_TYPE_ISSUE_COMMENT,
          id: @comment.id.to_s,
          graphql_global_relay_id: @comment.global_relay_id,
          graphql_next_global_id: @comment.next_global_id,
        ),
        related_entities: [Events::Entity.new(
          type: :ENTITY_TYPE_REPOSITORY,
          id: @repository.id.to_s,
          graphql_global_relay_id: @repository.global_relay_id,
          graphql_next_global_id: @repository.next_global_id,
        ), Events::Entity.new(
          type: :ENTITY_TYPE_ISSUE,
          id: @issue.id.to_s,
          graphql_global_relay_id: @issue.global_relay_id,
          graphql_next_global_id: @issue.next_global_id,
        )],
      ),
      actor: Events::Entity.new(
        type: :ENTITY_TYPE_USER,
        id: @actor.id.to_s,
        graphql_global_relay_id: @actor.global_relay_id,
        graphql_next_global_id: @actor.next_global_id,
      ),
      metadata: Events::Metadata.new(
        github_request_id: GitHub.context[:request_id],
        otel_trace_id: GitHub.current_span.context.hex_trace_id,
        disabled_for_import: false
      ),
      event_attachment: expected_attachment_value,
      target_repository_id: @repository.id,
      target_organization_id: @repository.organization_id,
      target_business_id: @repository.organization&.business&.id,
    )
    Events::Tier1EventPublisher.expects(:publish).with(expected_tier1_event, topic: "events_platform.v0.IssueComment")
    Events::IssueCommentPublisher.publish(tier1_event: expected_tier1_event)
  end
end
