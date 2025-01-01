# typed: true
# frozen_string_literal: true

require "test_helper"
require "hydro/schemas/github/event_payload_attachment/v0/issue_attachment_pb"
require "hydro/schemas/github/event_payload_attachment/v0/entities/issue_pb"

class Events::IssuesPublisherTest < GitHub::TestCase
  fixtures do
    @actor = create(:user)
    @org = create(:organization, admin: @actor)
    @repository = create(:public_repository, owner: @actor)
    @issue = create :issue, :with_instrumentation, user: @actor, title: "Hello", body: "World", repository: @repository
    @org_repo = create(:repository, owner: @org)
    @milestone = create(:milestone, repository: @org_repo)
    @deleted_issue = create(:issue, :with_instrumentation, user: @actor, repository: @org_repo, state_reason: :not_planned, milestone: @milestone, assignee: @actor)
    @mock_guid = "9dd711f0-54bb-11ef-8bdf-5708d685333a"
  end

  test "publishes issues opened event" do
    now = Time.now
    Timecop.freeze(now) do
      expected_tier1_event = Events::Tier1Event.new(
        type: :EVENT_TYPE_ISSUES,
        action: :EVENT_ACTION_OPENED,
        target: Events::Target.new(
          primary_entity: Events::Entity.new(
            type: :ENTITY_TYPE_ISSUE,
            id: @issue.id.to_s,
            graphql_global_relay_id: @issue.global_relay_id,
            graphql_next_global_id: @issue.next_global_id,
          ),
          related_entities: [Events::Entity.new(
            type: :ENTITY_TYPE_REPOSITORY,
            id: @repository.id.to_s,
            graphql_global_relay_id: @repository.global_relay_id,
            graphql_next_global_id: @repository.next_global_id,
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
          disabled_for_import: false,
          spammy_user_acting_outside_own_repos: false
        ),
        target_repository_id: @repository.id,
        target_organization_id: @repository.organization_id,
        target_business_id: @repository.organization&.business&.id,
        event_attachment: nil,
      )

      event_flags = Events::Tier1EventPublisher::EventFlags.new(
        webhook_deliveries_enabled: false,
        events_v2_validation_enabled: false,
        hookshot_deliveries_enabled: true,
        publish_tier1_events: true
      )

      Events::Tier1EventPublisher.expects(:publish).with(expected_tier1_event, topic: "events_platform.v0.Issues", event_flags: event_flags)

      Events::IssuesPublisher.opened(
        actor: @actor,
        repository: @repository,
        issue: @issue,
        event_flags: event_flags
      )
    end
  end

  test "does not generate issues opened event when pull request is created" do
    issue_with_pull_request_id = create :issue, :with_instrumentation, user: @actor, title: "Hello", body: "World"
    issue_with_pull_request_id.pull_request_id = 10
    event_flags = Events::Tier1EventPublisher::EventFlags.new(
      webhook_deliveries_enabled: false,
      events_v2_validation_enabled: false,
      hookshot_deliveries_enabled: true,
      publish_tier1_events: true
    )
    Events::Tier1EventPublisher.expects(:publish).never
    Events::IssuesPublisher.opened(actor: @actor, repository: @repository, issue: issue_with_pull_request_id, event_flags: event_flags)
  end

  test "publishes event with provided GUID" do
    now = Time.now

    Timecop.freeze(now) do
      expected_tier1_event = Events::Tier1Event.new(
        guid: @mock_guid,
        type: :EVENT_TYPE_ISSUES,
        action: :EVENT_ACTION_OPENED,
        target: Events::Target.new(
          primary_entity: Events::Entity.new(
            type: :ENTITY_TYPE_ISSUE,
            id: @issue.id.to_s,
            graphql_global_relay_id: @issue.global_relay_id,
            graphql_next_global_id: @issue.next_global_id,
          ),
          related_entities: [Events::Entity.new(
            type: :ENTITY_TYPE_REPOSITORY,
            id: @repository.id.to_s,
            graphql_global_relay_id: @repository.global_relay_id,
            graphql_next_global_id: @repository.next_global_id,
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
          disabled_for_import: false,
          spammy_user_acting_outside_own_repos: false
        ),
        target_repository_id: @repository.id,
        target_organization_id: @repository.organization_id,
        target_business_id: @repository.organization&.business&.id,
        event_attachment: nil,
      )

      event_flags = Events::Tier1EventPublisher::EventFlags.new(
        webhook_deliveries_enabled: false,
        events_v2_validation_enabled: false,
        hookshot_deliveries_enabled: true,
        publish_tier1_events: true
      )

      Events::Tier1EventPublisher.expects(:new_guid).never
      Events::Tier1EventPublisher.expects(:publish).with(expected_tier1_event, topic: "events_platform.v0.Issues", event_flags: event_flags)

      Events::IssuesPublisher.opened(
        actor: @actor,
        repository: @repository,
        issue: @issue,
        guid: @mock_guid,
        event_flags: event_flags
      )
    end
  end

  test "publishes event with spammy user", spammy_only: true do
    spammy_actor = create(:spammy_user)
    now = Time.now

    Timecop.freeze(now) do
      expected_tier1_event = Events::Tier1Event.new(
        guid: @mock_guid,
        type: :EVENT_TYPE_ISSUES,
        action: :EVENT_ACTION_OPENED,
        target: Events::Target.new(
          primary_entity: Events::Entity.new(
            type: :ENTITY_TYPE_ISSUE,
            id: @issue.id.to_s,
            graphql_global_relay_id: @issue.global_relay_id,
            graphql_next_global_id: @issue.next_global_id,
          ),
          related_entities: [Events::Entity.new(
            type: :ENTITY_TYPE_REPOSITORY,
            id: @repository.id.to_s,
            graphql_global_relay_id: @repository.global_relay_id,
            graphql_next_global_id: @repository.next_global_id,
          )],
        ),
        actor: Events::Entity.new(
          type: :ENTITY_TYPE_USER,
          id: spammy_actor.id.to_s,
          graphql_global_relay_id: spammy_actor.global_relay_id,
          graphql_next_global_id: spammy_actor.next_global_id,
        ),
        metadata: Events::Metadata.new(
          github_request_id: GitHub.context[:request_id],
          otel_trace_id: GitHub.current_span.context.hex_trace_id,
          disabled_for_import: false,
          spammy_user_acting_outside_own_repos: true
        ),
        target_repository_id: @repository.id,
        target_organization_id: @repository.organization_id,
        target_business_id: @repository.organization&.business&.id,
        event_attachment: nil,
      )

      event_flags = Events::Tier1EventPublisher::EventFlags.new(
        webhook_deliveries_enabled: false,
        events_v2_validation_enabled: false,
        hookshot_deliveries_enabled: true,
        publish_tier1_events: true
      )

      Events::Tier1EventPublisher.expects(:new_guid).never
      Events::Tier1EventPublisher.expects(:publish).with(expected_tier1_event, topic: "events_platform.v0.Issues", event_flags: event_flags)

      Events::IssuesPublisher.opened(
        actor: spammy_actor,
        repository: @repository,
        issue: @issue,
        guid: @mock_guid,
        event_flags: event_flags
      )
    end
  end

  test "generate issues deleted event when feature flag enabled" do
    enable_feature_flag(:issue_types)
    @deleted_issue.update!(issue_type: @org.issue_types.first)

    now = Time.now

    Timecop.freeze(now) do
      issue_attachment = Hydro::Schemas::Github::EventPayloadAttachment::V0::IssueAttachment.new(
        issue: Hydro::Schemas::Github::EventPayloadAttachment::V0::Entities::Issue.new(
          id: @deleted_issue.id,
          repository_id: @org_repo.id,
          user_id: Google::Protobuf::Int64Value.new(value: @actor.id),
          issue_comments_count: @deleted_issue.issue_comments_count,
          number: @deleted_issue.number,
          position: @deleted_issue.position,
          title: Google::Protobuf::BytesValue.new(value: @deleted_issue.read_attribute_before_type_cast(:title)&.to_s),
          state: :OPEN,
          created_at: Google::Protobuf::Timestamp.new(seconds: @deleted_issue.created_at.to_i),
          updated_at: Google::Protobuf::Timestamp.new(seconds: @deleted_issue.updated_at.to_i),
          closed_at: nil,
          pull_request_id: nil,
          milestone_id: Google::Protobuf::Int64Value.new(value: @deleted_issue.milestone_id),
          assignee_id: Google::Protobuf::Int64Value.new(value: @deleted_issue.assignee_id),
          contributed_at_timestamp: Google::Protobuf::Int64Value.new(value: @deleted_issue.contributed_at_timestamp),
          contributed_at_offset: Google::Protobuf::Int32Value.new(value: @deleted_issue.contributed_at_offset),
          user_hidden: @deleted_issue.user_hidden,
          performed_by_integration_id: nil,
          has_pull_request: @deleted_issue&.has_pull_request,
          locked_at: nil,
          compressed_body: Google::Protobuf::BytesValue.new(value: @deleted_issue.read_attribute_before_type_cast(:compressed_body)&.to_s),
          issue_type_id: Google::Protobuf::Int64Value.new(value: @deleted_issue.issue_type_id),
          issue_state_reason: Google::Protobuf::StringValue.new(value: @deleted_issue.state_reason),
        )
      )
      event_attachment = Events::EventAttachment.new(
        type_url: "type.googleapis.com/hydro.schemas.github.event_payload_attachment.v0.IssueAttachment",
        message: T.unsafe(Hydro::Schemas::Github::EventPayloadAttachment::V0::IssueAttachment).encode(issue_attachment)
      )

      expected_tier1_event = Events::Tier1Event.new(
        guid: @mock_guid,
        type: :EVENT_TYPE_ISSUES,
        action: :EVENT_ACTION_DELETED,
        target: Events::Target.new(
          primary_entity: Events::Entity.new(
            type: :ENTITY_TYPE_ISSUE,
            id: @deleted_issue.id.to_s,
            graphql_global_relay_id: @deleted_issue.global_relay_id,
            graphql_next_global_id: @deleted_issue.next_global_id,
          ),
          related_entities: [Events::Entity.new(
            type: :ENTITY_TYPE_REPOSITORY,
            id: @org_repo.id.to_s,
            graphql_global_relay_id: @org_repo.global_relay_id,
            graphql_next_global_id: @org_repo.next_global_id,
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
          disabled_for_import: false,
          spammy_user_acting_outside_own_repos: false
        ),
        target_repository_id: @org_repo.id,
        target_organization_id: @org_repo.organization_id,
        target_business_id: @org_repo.organization&.business&.id,
        event_attachment: event_attachment,
      )

      issue_deleted_event = Events::IssuesPublisher.generate_deleted_tier1_event(
        actor: @actor,
        repository: @org_repo,
        issue: @deleted_issue,
        guid: @mock_guid
      )

      assert_equal expected_tier1_event, issue_deleted_event
    end
  end

  test "generate issues deleted event with nil fields when feature flag enabled" do
    @deleted_issue.update!(
      user_id: nil,
      assignee_id: nil,
      milestone_id: nil,
      created_at: nil,
      updated_at: nil,
      contributed_at_timestamp: nil,
      contributed_at_offset: nil,
      compressed_body: nil
    )

    now = Time.now
    # We can not transition state to nil or set title to nil
    Timecop.freeze(now) do
      issue_attachment = Hydro::Schemas::Github::EventPayloadAttachment::V0::IssueAttachment.new(
        issue: Hydro::Schemas::Github::EventPayloadAttachment::V0::Entities::Issue.new(
          id: @deleted_issue.id,
          repository_id: @org_repo.id,
          user_id: nil,
          issue_comments_count: @deleted_issue.issue_comments_count,
          number: @deleted_issue.number,
          position: @deleted_issue.position,
          title: Google::Protobuf::BytesValue.new(value: @deleted_issue.read_attribute_before_type_cast(:title)&.to_s),
          state: :OPEN,
          created_at: nil,
          updated_at: nil,
          closed_at: nil,
          pull_request_id: nil,
          milestone_id: nil,
          assignee_id: nil,
          contributed_at_timestamp: nil,
          contributed_at_offset: nil,
          user_hidden: @deleted_issue.user_hidden,
          performed_by_integration_id: nil,
          has_pull_request: @deleted_issue&.has_pull_request,
          locked_at: nil,
          compressed_body: nil,
          issue_type_id: nil,
          issue_state_reason: Google::Protobuf::StringValue.new(value: @deleted_issue.state_reason),
        )
      )
      event_attachment = Events::EventAttachment.new(
        type_url: "type.googleapis.com/hydro.schemas.github.event_payload_attachment.v0.IssueAttachment",
        message: T.unsafe(Hydro::Schemas::Github::EventPayloadAttachment::V0::IssueAttachment).encode(issue_attachment)
      )

      expected_tier1_event = Events::Tier1Event.new(
        guid: @mock_guid,
        type: :EVENT_TYPE_ISSUES,
        action: :EVENT_ACTION_DELETED,
        target: Events::Target.new(
          primary_entity: Events::Entity.new(
            type: :ENTITY_TYPE_ISSUE,
            id: @deleted_issue.id.to_s,
            graphql_global_relay_id: @deleted_issue.global_relay_id,
            graphql_next_global_id: @deleted_issue.next_global_id,
          ),
          related_entities: [Events::Entity.new(
            type: :ENTITY_TYPE_REPOSITORY,
            id: @org_repo.id.to_s,
            graphql_global_relay_id: @org_repo.global_relay_id,
            graphql_next_global_id: @org_repo.next_global_id,
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
          disabled_for_import: false,
          spammy_user_acting_outside_own_repos: false,
        ),
        target_repository_id: @org_repo.id,
        target_organization_id: @org_repo.organization_id,
        target_business_id: @org_repo.organization&.business&.id,
        event_attachment: event_attachment,
      )

      issue_deleted_event = Events::IssuesPublisher.generate_deleted_tier1_event(
        actor: @actor,
        repository: @org_repo,
        issue: @deleted_issue,
        guid: @mock_guid
      )
      assert_equal expected_tier1_event, issue_deleted_event
    end
  end

  test "generate issues deleted event with body contains UTF-8 when feature flag enabled" do
    @deleted_issue.body = "König, доброе"

    now = Time.now
    # We can not transition state to nil or set title to nil
    Timecop.freeze(now) do
      issue_attachment = Hydro::Schemas::Github::EventPayloadAttachment::V0::IssueAttachment.new(
        issue: Hydro::Schemas::Github::EventPayloadAttachment::V0::Entities::Issue.new(
          id: @deleted_issue.id,
          repository_id: @org_repo.id,
          user_id: Google::Protobuf::Int64Value.new(value: @actor.id),
          issue_comments_count: @deleted_issue.issue_comments_count,
          number: @deleted_issue.number,
          position: @deleted_issue.position,
          title: Google::Protobuf::BytesValue.new(value: @deleted_issue.read_attribute_before_type_cast(:title)&.to_s),
          state: :OPEN,
          created_at: Google::Protobuf::Timestamp.new(seconds: @deleted_issue.created_at.to_i),
          updated_at: Google::Protobuf::Timestamp.new(seconds: @deleted_issue.updated_at.to_i),
          closed_at: nil,
          pull_request_id: nil,
          milestone_id: Google::Protobuf::Int64Value.new(value: @deleted_issue.milestone_id),
          assignee_id: Google::Protobuf::Int64Value.new(value: @deleted_issue.assignee_id),
          contributed_at_timestamp: Google::Protobuf::Int64Value.new(value: @deleted_issue.contributed_at_timestamp),
          contributed_at_offset: Google::Protobuf::Int32Value.new(value: @deleted_issue.contributed_at_offset),
          user_hidden: @deleted_issue.user_hidden,
          performed_by_integration_id: nil,
          has_pull_request: @deleted_issue&.has_pull_request,
          locked_at: nil,
          compressed_body: Google::Protobuf::BytesValue.new(value: @deleted_issue.read_attribute_before_type_cast(:compressed_body)&.to_s.b),
          issue_type_id: nil,
          issue_state_reason: Google::Protobuf::StringValue.new(value: @deleted_issue.state_reason),
        )
      )
      event_attachment = Events::EventAttachment.new(
        type_url: "type.googleapis.com/hydro.schemas.github.event_payload_attachment.v0.IssueAttachment",
        message: T.unsafe(Hydro::Schemas::Github::EventPayloadAttachment::V0::IssueAttachment).encode(issue_attachment)
      )

      expected_tier1_event = Events::Tier1Event.new(
        guid: @mock_guid,
        type: :EVENT_TYPE_ISSUES,
        action: :EVENT_ACTION_DELETED,
        target: Events::Target.new(
          primary_entity: Events::Entity.new(
            type: :ENTITY_TYPE_ISSUE,
            id: @deleted_issue.id.to_s,
            graphql_global_relay_id: @deleted_issue.global_relay_id,
            graphql_next_global_id: @deleted_issue.next_global_id,
          ),
          related_entities: [Events::Entity.new(
            type: :ENTITY_TYPE_REPOSITORY,
            id: @org_repo.id.to_s,
            graphql_global_relay_id: @org_repo.global_relay_id,
            graphql_next_global_id: @org_repo.next_global_id,
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
        target_repository_id: @org_repo.id,
        target_organization_id: @org_repo.organization_id,
        target_business_id: @org_repo.organization&.business&.id,
        event_attachment: event_attachment,
      )

      issue_deleted_event = Events::IssuesPublisher.generate_deleted_tier1_event(
        actor: @actor,
        repository: @org_repo,
        issue: @deleted_issue,
        guid: @mock_guid
      )
      assert_equal expected_tier1_event, issue_deleted_event
    end
  end

  test "does not generate issues deleted event when repository do not exist disabled" do
    issue_without_repository = create :issue, :with_instrumentation, user: @actor, title: "Hello", body: "World"
    issue_without_repository.repository.destroy!
    issue_without_repository.reload
    tier1_event = Events::IssuesPublisher.generate_deleted_tier1_event(issue: issue_without_repository, guid: @mock_guid, actor: @actor, repository: nil)
    assert_nil tier1_event
  end

  test "publishes issues deleted event" do
    enable_feature_flag(:issue_types)
    @deleted_issue.update!(issue_type: @org.issue_types.first)

    now = Time.now

    Timecop.freeze(now) do
      issue_attachment = Hydro::Schemas::Github::EventPayloadAttachment::V0::IssueAttachment.new(
        issue: Hydro::Schemas::Github::EventPayloadAttachment::V0::Entities::Issue.new(
          id: @deleted_issue.id,
          repository_id: @org_repo.id,
          user_id: Google::Protobuf::Int64Value.new(value: @actor.id),
          issue_comments_count: @deleted_issue.issue_comments_count,
          number: @deleted_issue.number,
          position: @deleted_issue.position,
          title: Google::Protobuf::BytesValue.new(value: @deleted_issue.read_attribute_before_type_cast(:title)&.to_s),
          state: :OPEN,
          created_at: Google::Protobuf::Timestamp.new(seconds: @deleted_issue.created_at.to_i),
          updated_at: Google::Protobuf::Timestamp.new(seconds: @deleted_issue.updated_at.to_i),
          closed_at: nil,
          pull_request_id: nil,
          milestone_id: Google::Protobuf::Int64Value.new(value: @deleted_issue.milestone_id),
          assignee_id: Google::Protobuf::Int64Value.new(value: @deleted_issue.assignee_id),
          contributed_at_timestamp: Google::Protobuf::Int64Value.new(value: @deleted_issue.contributed_at_timestamp),
          contributed_at_offset: Google::Protobuf::Int32Value.new(value: @deleted_issue.contributed_at_offset),
          user_hidden: @deleted_issue.user_hidden,
          performed_by_integration_id: nil,
          has_pull_request: @deleted_issue&.has_pull_request,
          locked_at: nil,
          compressed_body: Google::Protobuf::BytesValue.new(value: @deleted_issue.read_attribute_before_type_cast(:compressed_body)&.to_s),
          issue_type_id: Google::Protobuf::Int64Value.new(value: @deleted_issue.issue_type_id),
          issue_state_reason: Google::Protobuf::StringValue.new(value: @deleted_issue.state_reason),
        )
      )
      event_attachment = Events::EventAttachment.new(
        type_url: "type.googleapis.com/hydro.schemas.github.event_payload_attachment.v0.IssueAttachment",
        message: T.unsafe(Hydro::Schemas::Github::EventPayloadAttachment::V0::IssueAttachment).encode(issue_attachment)
      )

      expected_tier1_event = Events::Tier1Event.new(
        guid: @mock_guid,
        type: :EVENT_TYPE_ISSUES,
        action: :EVENT_ACTION_DELETED,
        target: Events::Target.new(
          primary_entity: Events::Entity.new(
            type: :ENTITY_TYPE_ISSUE,
            id: @deleted_issue.id.to_s,
            graphql_global_relay_id: @deleted_issue.global_relay_id,
            graphql_next_global_id: @deleted_issue.next_global_id,
          ),
          related_entities: [Events::Entity.new(
            type: :ENTITY_TYPE_REPOSITORY,
            id: @org_repo.id.to_s,
            graphql_global_relay_id: @org_repo.global_relay_id,
            graphql_next_global_id: @org_repo.next_global_id,
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
        target_repository_id: @org_repo.id,
        target_organization_id: @org_repo.organization_id,
        target_business_id: @org_repo.organization&.business&.id,
        event_attachment: event_attachment,
      )
      issue_deleted_event = Events::IssuesPublisher.generate_deleted_tier1_event(
        actor: @actor,
        repository: @org_repo,
        issue: @deleted_issue,
        guid: @mock_guid
      )
      event_flags = Events::Tier1EventPublisher::EventFlags.new(
        webhook_deliveries_enabled: false,
        events_v2_validation_enabled: false,
        hookshot_deliveries_enabled: true,
        publish_tier1_events: true
      )

      Events::Tier1EventPublisher.expects(:new_guid).never

      Events::Tier1EventPublisher.expects(:publish).with(expected_tier1_event, topic: "events_platform.v0.Issues", event_flags: event_flags)

      Events::IssuesPublisher.publish_tier1_event(tier1_event: issue_deleted_event, event_flags: event_flags)
    end
  end
end
