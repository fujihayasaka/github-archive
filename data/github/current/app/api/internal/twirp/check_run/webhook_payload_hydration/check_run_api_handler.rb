# typed: true
# frozen_string_literal: true

require "monolith-twirp-event_hydrator-event_hydration"

class Api::Internal::Twirp::CheckRun::WebhookPayloadHydration::CheckRunApiHandler < Api::Internal::Twirp::Handler
  allow_access_for :client, allowed_clients: ["event_hydrator"]
  handles_service EventsPlatform::V1::CheckRunAPIService

  # Public: Implementation of the EventsPlatform::V1::CheckRunAPIService#Hydrate Twirp RPC.
  # https://github.com/github/event-hydrator/blob/main/proto/event_hydration/v1/services.proto
  #
  # req - The Twirp request as a EventsPlatform::V1::HydrateRequest.
  # env - The Twirp environment as a Hash.
  #
  # Returns the Twirp response as a Hash suitable for use in a
  # HydrateResponse, or a Twirp::Error.
  def hydrate(req, env)
    return Twirp::Error.invalid_argument("missing tier1_event", argument: "tier1_event") unless req.tier1_event
    return Twirp::Error.invalid_argument("invalid event type", argument: "event_type") if req.tier1_event.type != :EVENT_TYPE_CHECK_RUN

    allowed_actions = [
      :EVENT_ACTION_CREATED,
      :EVENT_ACTION_COMPLETED,
      :EVENT_ACTION_REREQUESTED,
      :EVENT_ACTION_REQUESTED_ACTION,
    ]
    return Twirp::Error.invalid_argument("invalid event action", argument: "action") unless allowed_actions.include?(req.tier1_event.action)

    Events::Domain::DefaultHydration.hydrate(
      event_class: Hook::Event::CheckRunEvent,
      attributes_class: Hydro::Schemas::Github::HookEventAttributes::V0::CheckRunEventAttributes,
      req: req,
    )

  rescue Exception => e # rubocop:todo Lint/RescueException
    Twirp::Error.internal("Failed to hydrate payload. Error: #{e.message}", argument: "tier1_event")
  end
end
