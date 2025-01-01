# typed: true
# frozen_string_literal: true

require "monolith-twirp-event_hydrator-event_hydration"

class Api::Internal::Twirp::PullRequests::WebhookPayloadHydration::PullRequestReviewApiHandler < Api::Internal::Twirp::Handler
  include Events::Domain::Provider

  allow_access_for :client, allowed_clients: ["event_hydrator"]
  handles_service EventsPlatform::V1::PullRequestReviewAPIService

  # Public: Implementation of the EventsPlatform::V1::PullRequestReviewApiHandlerAPIService#Hydrate Twirp RPC.
  # https://github.com/github/event-hydrator/blob/fb9b4a011c0dfc573e5cc88c36d0818387152984/proto/event_hydration/v1/services.proto
  #
  # req - The Twirp request as a EventsPlatform::V1::HydrateRequest.
  # env - The Twirp environment as a Hash.
  #
  # Returns the Twirp response as a Hash suitable for use in a
  # HydrateResponse, or a Twirp::Error.
  def hydrate(req, env)
    return Twirp::Error.invalid_argument("missing tier1_event", argument: "tier1_event") unless req.tier1_event
    return Twirp::Error.invalid_argument("invalid event type", argument: "event_type") if req.tier1_event.type != :EVENT_TYPE_PULL_REQUEST_REVIEW

    action = events_domain.action_for_event_action_enum(req.tier1_event.action)
    tier1_event = req.tier1_event

    repository = get_repository(tier1_event)
    return resource_not_found_resp unless repository

    pull_request_review = get_pull_request_review(tier1_event)
    return resource_not_found_resp unless pull_request_review || req.tier1_event.action == :EVENT_ACTION_DELETED
    payload = {
      action: action,
      review: events_domain.api_serialize(:pull_request_review_hash, pull_request_review),
      pull_request: events_domain.api_serialize(:pull_request_hash, pull_request_review&.pull_request),
    }

    organization = get_organization(tier1_event)
    business = get_business(tier1_event)
    actor = get_actor(tier1_event)

    payload[:organization] = events_domain.api_serialize(:organization_hash, organization) if organization
    payload[:enterprise] = events_domain.api_serialize(:business_hash, business) if business
    payload[:sender] = events_domain.api_serialize(:user_hash, actor) if actor
    payload[:repository] = events_domain.api_serialize(:repository_with_custom_properties_hash, repository)

    payload_version_result = {
      code: :RESULT_CODE_SUCCESS,
      payload: payload.to_json
    }

    target_repository_disabled_webhooks = events_domain.has_target_repository_disabled_webhooks(repository)
    { results: [payload_version_result], has_target_repository_disabled_webhooks: target_repository_disabled_webhooks }

  rescue Exception => e # rubocop:todo Lint/GenericRescue
    Twirp::Error.internal("Failed to hydrate payload. Error: #{e.message}", argument: "tier1_event")
  end

  private

  # Private: Reads actor ID and uses it to query for the actor for this event from the database.
  def get_actor(tier1_event)
    return unless tier1_event.actor&.id
    User.find_by(id: tier1_event.actor.id)
  end

  # Private: Reads the target_organization_id and uses it to query for the organization for this event from the
  # database.
  def get_organization(tier1_event)
    return unless tier1_event.target_organization_id&.value
    Organization.find_by(id: tier1_event.target_organization_id.value)
  end

  # Private: Reads the target_business_id and uses it to query for the business for this event from the
  # database.
  def get_business(tier1_event)
    return unless tier1_event.target_business_id&.value
    Business.find_by(id: tier1_event.target_business_id.value)
  end

  # Private: Reads the target_repository_id and uses it to query for the repository for this event from the
  # database.
  def get_repository(tier1_event)
    return unless tier1_event&.target_repository_id&.value
    Repository.find_by(id: tier1_event.target_repository_id.value)
  end

  def get_pull_request_review(tier1_event)
    return if tier1_event&.target&.primary_entity.nil? || tier1_event.target.primary_entity.type != :ENTITY_TYPE_PULL_REQUEST_REVIEW
    PullRequestReview.find_by(id: tier1_event.target.primary_entity.id)
  end

  def resource_not_found_resp
    payload_version_result = {
      code: :RESULT_CODE_RESOURCE_NOT_FOUND,
      payload: nil
    }
    { results: [payload_version_result], has_target_repository_disabled_webhooks: false }
  end
end
