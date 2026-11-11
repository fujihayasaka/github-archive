# typed: strict
# frozen_string_literal: true

require "monolith-twirp-event_hydrator-event_hydration"

class Api::Internal::Twirp::Webhooks::Ping::WebhookPayloadHydration::PingApiHandler < Api::Internal::Twirp::Handler
  allow_access_for :client, allowed_clients: ["event_hydrator"]
  handles_service EventsPlatform::V1::PingAPIService

  # Public: Implementation of the EventsPlatform::V1::PingAPIService#Hydrate Twirp RPC.
  # https://github.com/github/event-hydrator/blob/main/proto/event_hydration/v1/services.proto
  #
  # req - The Twirp request as a EventsPlatform::V1::HydrateRequest.
  # env - The Twirp environment as a Hash.
  #
  # Returns the Twirp response as a Hash suitable for use in a
  # HydrateResponse, or a Twirp::Error.
  sig { params(req: EventsPlatform::V1::HydrateRequest, env: T::Hash[Symbol, T.untyped]).returns(T.any(T::Hash[Symbol, T.untyped], Twirp::Error)) }
  def hydrate(req, env)
    return Twirp::Error.invalid_argument("missing tier1_event", argument: "tier1_event") unless req.tier1_event.present?
    tier1_event = T.must(req.tier1_event)
    return Twirp::Error.invalid_argument("invalid event type", argument: "event_type") if tier1_event.type  != :EVENT_TYPE_PING
    return Twirp::Error.invalid_argument("invalid event action", argument: "action") if tier1_event.action  != :EVENT_ACTION_NONE

    Events::Domain::DefaultHydration.hydrate(
      event_class: Hook::Event::PingEvent,
      attributes_class: Hydro::Schemas::Github::HookEventAttributes::V0::PingEventAttributes,
      req: req,
    )
  end
end
