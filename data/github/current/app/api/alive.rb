# typed: true
# frozen_string_literal: true

class Api::Alive < Api::App
  # Generates the URL of the Alive web socket, given a session_id.
  get "/alive_internal/websocket-url", operation_id: :internal do
    @route_owner = "@github/ecosystem-events-reviewers"

    control_access :alive_events_subscriber,
      resource: current_user,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    url = GitHub::WebSocket.websocket_url(nil, current_user.id)

    deliver_raw({ url: url })
  end
end
