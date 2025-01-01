# typed: true
# frozen_string_literal: true

require "monolith-twirp-event_hydrator-event_hydration"

class Api::Internal::Twirp::Issues::WebhookPayloadHydration::IssuesEventApiHandler < Api::Internal::Twirp::Handler
  include Events::Domain::Provider

  allow_access_for :client, allowed_clients: ["event_hydrator"]
  handles_service EventsPlatform::V1::IssuesAPIService

  # Public: Implementation of the HydrateEvent Twirp RPC.
  #
  # req - The Twirp request as a EventsPlatform::V1::HydrateRequest.
  # env - The Twirp environment as a Hash.
  #
  # Returns the Twirp response as a Hash suitable for use in a
  # HydrateResponse, or a Twirp::Error.
  def hydrate(req, env)
    return Twirp::Error.invalid_argument("missing tier1_event", argument: "tier1_event") unless req.tier1_event
    return Twirp::Error.invalid_argument("invalid event type", argument: "event_type") if req.tier1_event.type.empty? || req.tier1_event.type != :EVENT_TYPE_ISSUES
    return Twirp::Error.invalid_argument("missing payload_versions", argument: "payload_versions") unless req.payload_versions.present?

    action = events_domain.action_for_event_action_enum(req.tier1_event.action)
    tier1_event = req.tier1_event
    requested_versions = req.payload_versions

    repository = get_repository(tier1_event)
    return Twirp::Error.not_found("repository not found", entity: "repository") unless repository

    issue = get_issue(tier1_event)
    return Twirp::Error.not_found("issue not found", entity: "issue") unless issue

    organization = get_organization(tier1_event)
    business = get_business(tier1_event)
    actor = get_actor(tier1_event)

    versioned_payloads = requested_versions.map do |version|
      Events::Domain::VersionedPayload.new(version, { action: action }) do |p|
        p.serialize(:issue, :issue_hash, issue)
        p.serialize(:repository, :repository_with_custom_properties_hash, repository)
        p.serialize(:organization, :organization_hash, organization) if organization
        p.serialize(:enterprise, :business_hash, business) if business
        p.serialize(:sender, :user_hash, actor) if actor
      end.to_h
    end

    has_target_repository_disabled_webhooks = events_domain.has_target_repository_disabled_webhooks(repository)
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
    Repository.find_by(id: tier1_event.target_repository_id.value)
  end

  def get_issue(tier1_event)
    return if tier1_event&.target&.primary_entity.nil? || tier1_event.target.primary_entity.type != :ENTITY_TYPE_ISSUE

    if tier1_event.action == :EVENT_ACTION_DELETED
      attachment_bytes = tier1_event.event_attachment.message
      attachment = T.unsafe(Hydro::Schemas::Github::EventPayloadAttachment::V0::IssueAttachment).decode(attachment_bytes)
      in_memory_issue(attachment)
    else
      Issue.find_by(id: tier1_event.target.primary_entity.id)
    end
  end

  def in_memory_issue(attrs)
    return unless attrs.issue
    issue_attachment = attrs.issue
    compressed_body = issue_attachment.compressed_body&.value
    title = issue_attachment.title&.value
    compressed_body = Zstd.decompress(compressed_body) if compressed_body

    Issue.new(
      id: issue_attachment.id,
      repository_id: issue_attachment.repository_id,
      user_id: issue_attachment.user_id&.value,
      issue_comments_count: issue_attachment.issue_comments_count,
      number: issue_attachment.number,
      position: issue_attachment.position,
      title: title,
      state: issue_attachment.state.downcase,
      created_at: Time.at(issue_attachment.created_at.seconds),
      updated_at: Time.at(issue_attachment.updated_at.seconds),
      closed_at: issue_attachment.closed_at ? Time.at(issue_attachment.closed_at.seconds) : nil,
      pull_request_id: issue_attachment.pull_request_id&.value,
      milestone_id: issue_attachment.milestone_id&.value,
      assignee_id: issue_attachment.assignee_id&.value,
      contributed_at_timestamp: issue_attachment.contributed_at_timestamp&.value,
      contributed_at_offset:  issue_attachment.contributed_at_offset&.value,
      user_hidden: issue_attachment.user_hidden,
      performed_by_integration_id: issue_attachment.performed_by_integration_id&.value,
      has_pull_request: issue_attachment.has_pull_request,
      locked_at: issue_attachment.locked_at ? Time.at(issue_attachment.locked_at.seconds) : nil,
      compressed_body: compressed_body,
      state_reason: issue_attachment.state_reason&.value,
    )
  end
end
