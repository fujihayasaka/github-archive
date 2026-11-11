# typed: true
# frozen_string_literal: true

require "monolith-twirp-event_hydrator-event_hydration"

class Api::Internal::Twirp::PullRequests::WebhookPayloadHydration::PullRequestReviewApiHandler < Api::Internal::Twirp::Handler
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
    return Twirp::Error.invalid_argument("missing payload_versions", argument: "payload_versions") unless req.payload_versions.present?

    action = Events::Domain.domain.action_for_event_action_enum(req.tier1_event.action)
    tier1_event = req.tier1_event
    requested_versions = req.payload_versions

    replication_data = Events::Domain.domain.replication_data(req.tier1_event&.metadata&.tracked_writes, :EVENT_TYPE_PULL_REQUEST_REVIEW)
    return Twirp::Error.failed_precondition("replication incomplete") unless replication_data.exceeded_maximum_timeout? || replication_data.replications_completed?

    repository = get_repository(tier1_event)
    return Twirp::Error.not_found("respository not found", entity: "respository") unless repository

    pull_request_review = get_pull_request_review(tier1_event)
    return Twirp::Error.not_found("pull request review not found", entity: "pull_request_review") unless pull_request_review

    organization = get_organization(tier1_event)
    business = get_business(tier1_event)
    actor = get_actor(tier1_event)

    versioned_payloads = requested_versions.map do |version|
      Events::Domain::VersionedPayload.new(version, { action: action }) do |p|
        p.serialize(:review, :pull_request_review_hash, pull_request_review)
        p.serialize(:pull_request, :pull_request_hash, pull_request_review&.pull_request, hook: true, show_merge_settings: true)
        p.serialize(:repository, :repository_with_custom_properties_hash, repository)
        p.serialize(:organization, :organization_hash, organization) if organization
        p.serialize(:enterprise, :business_hash, business) if business
        p.serialize(:sender, :user_hash, actor) if actor
      end.to_h
    end

    has_target_repository_disabled_webhooks = Events::Domain.domain.has_target_repository_disabled_webhooks(repository)
    {
      results: versioned_payloads,
      has_target_repository_disabled_webhooks: has_target_repository_disabled_webhooks
    }
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
    Repositories.domain.by_id(tier1_event.target_repository_id.value)
  end

  def get_pull_request_review(tier1_event)
    return if tier1_event&.target&.primary_entity.nil? || tier1_event.target.primary_entity.type != :ENTITY_TYPE_PULL_REQUEST_REVIEW
    PullRequestReview.find_by(id: tier1_event.target.primary_entity.id)
  end
end
