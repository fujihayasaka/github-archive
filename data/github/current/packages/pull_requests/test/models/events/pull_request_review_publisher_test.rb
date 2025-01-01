# typed: true
# frozen_string_literal: true

require "test_helper"

class Events::PullRequestReviewPublisherTest < GitHub::TestCase
  fixtures do
    @owner = create(:user, login: "owner", plan: "micro")
    @forker = create(:user)
    @admin = TestEnv.test_with_all_emus? ? create(:user) : create(:staff_admin_user)

    @source = create(:private_repository, owner: @owner, name: "source", from_example: :review_comment_fork)
    create(:collaborator, collaborator: @forker, repository: @source, action: :write)
    create(:collaborator, collaborator: @admin, repository:  @source, action: :write)

    @fork = create(:fork_repository, forker: @forker, fork_repo: @source, from_example: :review_comment_fork)

    @org = create :organization, login: "acme", admin: @owner
    @team = create(:team, organization: @org, name: "team_dog", privacy: :closed)
    @org_repo = create(:repository, owner: @org, from_example: :pull_request_source)
    create(:collaborator, collaborator: @forker, repository: @org_repo, action: :write)
    create(:collaborator, collaborator: @admin, repository:  @org_repo, action: :write)
    create(:collaborator, collaborator: @owner, repository:  @org_repo, action: :write)
    @team.add_member @forker, adder: @owner
    @team.add_repository(@org_repo, :push)

    @issue = create(:issue, user: @forker, repository: @source)
    @pull =
      create(:pull_request,
        repository: @source,
        base_repository: @source,
        base_user: @source.owner,
        base_ref: "master",
        head_repository: @fork,
        head_user: @fork.owner,
        head_ref: "topic",
        issue: @issue,
        user: @forker,
      )
    @issue.pull_request = @pull
    @review = @pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: @forker, body: "bod")
  end

  test "publishes pull request review submitted event" do
    now = Time.now

    Timecop.freeze(now) do
      expected_tier1_event = Events::Tier1Event.new(
        type: :EVENT_TYPE_PULL_REQUEST_REVIEW,
        action: :EVENT_ACTION_SUBMITTED,
        target: Events::Target.new(
          primary_entity: Events::Entity.new(
            type: :ENTITY_TYPE_PULL_REQUEST_REVIEW,
            id: @review.id.to_s,
            graphql_global_relay_id: @review.global_relay_id,
            graphql_next_global_id: @review.next_global_id,
          ),
          related_entities: [Events::Entity.new(
            type: :ENTITY_TYPE_PULL_REQUEST,
            id: @review.pull_request.id.to_s,
            graphql_global_relay_id: @review.pull_request.global_relay_id,
            graphql_next_global_id: @review.pull_request.next_global_id,
          )],
        ),
        actor: Events::Entity.new(
          type: :ENTITY_TYPE_USER,
          id: @review.user.id.to_s,
          graphql_global_relay_id: @review.user.global_relay_id,
          graphql_next_global_id: @review.user.next_global_id,
        ),
        metadata: Events::Metadata.new(
          github_request_id: GitHub.context[:request_id],
          otel_trace_id: GitHub.current_span.context.hex_trace_id,
          disabled_for_import: false,
        ),
        target_repository_id: @review.repository.id,
        target_organization_id: @review.repository.organization_id,
        target_business_id: @review.repository.organization&.business_id,
      )

      event_flags = Events::Tier1EventPublisher::EventFlags.new(
        webhook_deliveries_enabled: false,
        hookshot_deliveries_enabled: true,
        events_v2_validation_enabled: false,
        publish_tier1_events: true,
      )

      Events::Tier1EventPublisher.expects(:publish).with(expected_tier1_event, topic: "events_platform.v0.PullRequestReview", event_flags: event_flags)
      Events::PullRequestReviewPublisher.submitted(@review)
    end
  end

  test "publishes pull request review event with provided GUID" do
    now = Time.now
    Timecop.freeze(now) do
      provided_guid = "46235fe0-53ee-11ef-8e99-575fbb4a1854"
      expected_tier1_event = Events::Tier1Event.new(
        guid: provided_guid,
        type: :EVENT_TYPE_PULL_REQUEST_REVIEW,
        action: :EVENT_ACTION_SUBMITTED,
        target: Events::Target.new(
          primary_entity: Events::Entity.new(
            type: :ENTITY_TYPE_PULL_REQUEST_REVIEW,
            id: @review.id.to_s,
            graphql_global_relay_id: @review.global_relay_id,
            graphql_next_global_id: @review.next_global_id,
          ),
          related_entities: [Events::Entity.new(
            type: :ENTITY_TYPE_PULL_REQUEST,
            id: @review.pull_request.id.to_s,
            graphql_global_relay_id: @review.pull_request.global_relay_id,
            graphql_next_global_id: @review.pull_request.next_global_id,
          )],
        ),
        actor: Events::Entity.new(
          type: :ENTITY_TYPE_USER,
          id: @review.user.id.to_s,
          graphql_global_relay_id: @review.user.global_relay_id,
          graphql_next_global_id: @review.user.next_global_id,
        ),
        metadata: Events::Metadata.new(
          github_request_id: GitHub.context[:request_id],
          otel_trace_id: GitHub.current_span.context.hex_trace_id,
          disabled_for_import: false,
        ),
        target_repository_id: @review.repository.id,
        target_organization_id: @review.repository.organization_id,
        target_business_id: @review.repository.organization&.business_id,
      )

      Events::Tier1EventPublisher.expects(:new_guid).never
      event_flags = Events::Tier1EventPublisher::EventFlags.new(
        webhook_deliveries_enabled: false,
        hookshot_deliveries_enabled: true,
        events_v2_validation_enabled: false,
        publish_tier1_events: true,
      )

      Events::Tier1EventPublisher.expects(:publish).with(expected_tier1_event, topic: "events_platform.v0.PullRequestReview", event_flags: event_flags)
      Events::PullRequestReviewPublisher.submitted(@review, event_guid: provided_guid)
    end
  end

  test "publishes pull request review event with spammy actor", spammy_only: true do
    now = Time.now
    spammy_actor = create(:spammy_user)
    @review.update!(user: spammy_actor)

    Timecop.freeze(now) do
      provided_guid = "46235fe0-53ee-11ef-8e99-575fbb4a1854"
      expected_tier1_event = Events::Tier1Event.new(
        guid: provided_guid,
        type: :EVENT_TYPE_PULL_REQUEST_REVIEW,
        action: :EVENT_ACTION_SUBMITTED,
        target: Events::Target.new(
          primary_entity: Events::Entity.new(
            type: :ENTITY_TYPE_PULL_REQUEST_REVIEW,
            id: @review.id.to_s,
            graphql_global_relay_id: @review.global_relay_id,
            graphql_next_global_id: @review.next_global_id,
          ),
          related_entities: [Events::Entity.new(
            type: :ENTITY_TYPE_PULL_REQUEST,
            id: @review.pull_request.id.to_s,
            graphql_global_relay_id: @review.pull_request.global_relay_id,
            graphql_next_global_id: @review.pull_request.next_global_id,
          )],
        ),
        actor: Events::Entity.new(
          type: :ENTITY_TYPE_USER,
          id: @review.user.id.to_s,
          graphql_global_relay_id: @review.user.global_relay_id,
          graphql_next_global_id: @review.user.next_global_id,
        ),
        metadata: Events::Metadata.new(
          github_request_id: GitHub.context[:request_id],
          otel_trace_id: GitHub.current_span.context.hex_trace_id,
          disabled_for_import: false,
          spammy_user_acting_outside_own_repos: true
        ),
        target_repository_id: @review.repository.id,
        target_organization_id: @review.repository.organization_id,
        target_business_id: @review.repository.organization&.business_id,
      )

      event_flags = Events::Tier1EventPublisher::EventFlags.new(
        webhook_deliveries_enabled: false,
        hookshot_deliveries_enabled: true,
        events_v2_validation_enabled: false,
        publish_tier1_events: true,
      )

      Events::Tier1EventPublisher.expects(:new_guid).never
      Events::Tier1EventPublisher.expects(:publish).with(expected_tier1_event, topic: "events_platform.v0.PullRequestReview", event_flags: event_flags)
      Events::PullRequestReviewPublisher.submitted(@review, event_guid: provided_guid)
    end
  end
end
