# typed: strict
# frozen_string_literal: true

class Events::PullRequestReviewPublisher
  extend PullRequests::Copilot::CodeReviewHelper

  sig { params(review: PullRequestReview, event_flags: Events::Tier1EventPublisher::EventFlags, event_guid: T.nilable(String)).void }
  def self.submitted(review, event_flags:, event_guid: nil)
    repository = review.repository
    actor = review.user

    return if is_empty_copilot_review?(pull_request_review_id: review.id, actor_id: actor&.id)

    events_domain = Events::Domain.domain

    metadata = Events::Metadata.new(
      github_request_id: GitHub.context[:request_id],
      otel_trace_id: GitHub.current_span.context.hex_trace_id,
      disabled_for_import: events_domain.model_importing?(review.repository),
      spammy_user_acting_outside_own_repos: actor&.spammy?
    )
    actor_graphql_ids = events_domain.graphql_ids(actor)
    tier1_actor = Events::Entity.new(
      type: :ENTITY_TYPE_USER,
      id: actor&.id.to_s,
      graphql_global_relay_id: actor_graphql_ids.global_relay_id,
      graphql_next_global_id: actor_graphql_ids.next_global_id,
    )

    pull_request_ids = events_domain.graphql_ids(review.pull_request)
    pull_request_review_ids = events_domain.graphql_ids(review)

    primary_entity = Events::Entity.new(
      type: :ENTITY_TYPE_PULL_REQUEST_REVIEW,
      id: review.id.to_s,
      graphql_global_relay_id: pull_request_review_ids.global_relay_id,
      graphql_next_global_id: pull_request_review_ids.next_global_id,
    )
    related_entity = Events::Entity.new(
      type: :ENTITY_TYPE_PULL_REQUEST,
      id: review.pull_request&.id.to_s,
      graphql_global_relay_id:  pull_request_ids.global_relay_id,
      graphql_next_global_id: pull_request_ids.next_global_id,
    )
    target = Events::Target.new(
      primary_entity: primary_entity,
      related_entities: [related_entity],
    )
    tier1_event_message = Events::Tier1Event.new(
      type: :EVENT_TYPE_PULL_REQUEST_REVIEW,
      action: :EVENT_ACTION_SUBMITTED,
      target: target,
      actor: tier1_actor,
      metadata: metadata,
      guid: event_guid,
      target_repository_id: repository&.id,
      target_organization_id: repository&.organization_id,
      target_business_id: repository&.organization&.business&.id,
    )

    Events::Tier1EventPublisher.publish(tier1_event_message, topic: "events_platform.v0.PullRequestReview", event_flags: event_flags)
  end
end
