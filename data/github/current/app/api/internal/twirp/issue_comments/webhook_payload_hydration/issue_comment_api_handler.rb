# typed: true
# frozen_string_literal: true

require "monolith-twirp-event_hydrator-event_hydration"
require "hydro/schemas/github/event_payload_attachment/v0/issue_comment_attachment_pb"

class Api::Internal::Twirp::IssueComments::WebhookPayloadHydration::IssueCommentApiHandler < Api::Internal::Twirp::Handler
  include Events::Domain::Provider

  allow_access_for :client, allowed_clients: ["event_hydrator"]
  handles_service EventsPlatform::V1::IssueCommentAPIService

  # Public: Implementation of the EventsPlatform::V1::IssueCommentAPIService#Hydrate Twirp RPC.
  # https://github.com/github/event-hydrator/blob/main/proto/event_hydration/v1/services.proto
  #
  # req - The Twirp request as a EventsPlatform::V1::HydrateRequest.
  # env - The Twirp environment as a Hash.
  #
  # Returns the Twirp response as a Hash suitable for use in a
  # HydrateResponse, or a Twirp::Error.
  def hydrate(req, env)
    return Twirp::Error.invalid_argument("missing tier1_event", argument: "tier1_event") unless req.tier1_event
    return Twirp::Error.invalid_argument("invalid event type", argument: "event_type") if req.tier1_event.type != :EVENT_TYPE_ISSUE_COMMENT

    action = events_domain.action_for_event_action_enum(req.tier1_event.action)
    tier1_event = req.tier1_event

    issue = get_issue(tier1_event)
    return resource_not_found_resp unless issue

    repository = get_repository(tier1_event)
    return resource_not_found_resp unless repository

    # For now, only the deleted action is implemented.
    return Twirp::Error.internal("Failed to hydrate payload. Action #{action} is not yet implemented.") if action != "deleted"

    issue_comment = get_issue_comment(tier1_event)
    return resource_not_found_resp unless issue_comment

    payload = {
      action: action,
      issue: events_domain.api_serialize(:issue_hash, issue),
      comment: events_domain.api_serialize(:issue_comment_hash, issue_comment)
    }

    organization = get_organization(tier1_event)
    business = get_business(tier1_event)
    actor = get_actor(tier1_event)
    payload[:repository] = events_domain.api_serialize(:repository_with_custom_properties_hash, repository)
    payload[:organization] = events_domain.api_serialize(:organization_hash, organization) if organization
    payload[:enterprise] = events_domain.api_serialize(:business_hash, business) if business
    payload[:sender] = events_domain.api_serialize(:user_hash, actor) if actor

    payload_version_result = {
      code: :RESULT_CODE_SUCCESS,
      payload: payload.to_json
    }
    {
      results: [payload_version_result],
      has_target_repository_disabled_webhooks: events_domain.has_target_repository_disabled_webhooks(repository)
    }
  rescue Exception => e # rubocop:todo Lint/GenericRescue
    Twirp::Error.internal("Failed to hydrate payload. Error: #{e.message}", argument: "tier1_event")
  end

  private

  def resource_not_found_resp
    payload_version_result = {
      code: :RESULT_CODE_RESOURCE_NOT_FOUND,
      payload: nil
    }
    { results: [payload_version_result], has_target_repository_disabled_webhooks: false }
  end

  # Private: Reads actor ID and uses it to query for the actor for this event from the database.
  def get_actor(tier1_event)
    return unless tier1_event.actor&.id
    User.find_by id: tier1_event.actor.id
  end

  # Private: Reads the target_organization_id and uses it to query for the organization for this event from the
  # database.
  def get_organization(tier1_event)
    return unless tier1_event.target_organization_id&.value
    Organization.find_by id: tier1_event.target_organization_id.value
  end

  # Private: Reads the target_business_id and uses it to query for the business for this event from the
  # database.
  def get_business(tier1_event)
    return unless tier1_event.target_business_id&.value
    Business.find_by id: tier1_event.target_business_id.value
  end

  # Private: Reads the target_repository_id and uses it to query for the repository for this event from the
  # database.
  def get_repository(tier1_event)
    return unless tier1_event&.target_repository_id&.value
    Repository.find_by(id: tier1_event.target_repository_id.value)
  end

  def get_issue(tier1_event)
    return unless tier1_event&.target&.related_entities&.length > 0
    issue_entity = tier1_event.target.related_entities.find do |entity|
      Hydro::Schemas::EventsPlatform::V0::Entities::EntityType.resolve(entity.type) == Hydro::Schemas::EventsPlatform::V0::Entities::EntityType::ENTITY_TYPE_ISSUE
    end
    return unless issue_entity&.id
    Issue.find_by id: issue_entity.id
  end

  def get_issue_comment(tier1_event)
    if tier1_event.action == :EVENT_ACTION_DELETED
      attachment_bytes = tier1_event.event_attachment.message
      attachment = T.unsafe(Hydro::Schemas::Github::EventPayloadAttachment::V0::IssueCommentAttachment).decode(attachment_bytes)
      in_memory_issue_comment(attachment)
    end
  end

  def in_memory_issue_comment(attrs)
    return unless attrs.issue_comment
    issue_comment_attachment = attrs.issue_comment

    compressed_body = attrs.issue_comment.compressed_body&.value
    compressed_body = Zstd.decompress(compressed_body) if compressed_body

    issue_comment = IssueComment.new(
      id: issue_comment_attachment.id,
      issue_id: issue_comment_attachment.issue_id,
      user_id: issue_comment_attachment.user_id&.value,
      created_at: Time.at(issue_comment_attachment.created_at.seconds),
      updated_at: Time.at(issue_comment_attachment.updated_at.seconds),
      repository_id: issue_comment_attachment.repository_id,
      formatter: issue_comment_attachment.formatter&.value,
      user_hidden: issue_comment_attachment.user_hidden,
      performed_by_integration_id: issue_comment_attachment.performed_by_integration_id&.value,
      comment_hidden: issue_comment_attachment.comment_hidden,
      comment_hidden_reason: issue_comment_attachment.comment_hidden_reason&.value,
      comment_hidden_classifier: issue_comment_attachment.comment_hidden_classifier&.value,
      comment_hidden_by: issue_comment_attachment.comment_hidden_by&.value,
      compressed_body: compressed_body
    )

    return issue_comment if attrs.issue_comment_reactions_count.empty?

    reactions_map = attrs.issue_comment_reactions_count.each_with_object({}) do |reaction, reaction_map|
      reaction_map[reaction.content] = reaction.count
    end
    issue_comment.reactions_count = reactions_map
    issue_comment
  end
end
