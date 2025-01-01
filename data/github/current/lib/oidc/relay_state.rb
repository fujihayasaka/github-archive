# typed: true
# frozen_string_literal: true

require "relay_state"
require "github/external_identities/kv"

module OIDC
  # A class to manage OIDC request/response relay state.
  #
  # Provides an opaque token for use as the `RelayState` during request
  # phase and consumed within the callback method called from omni-auth strategy
  #
  # It is designed to persist state like the `return_to` URL, as well as some additional data like
  # business id and setup parameter
  #
  # It also verifies the integrity of the relay state by requiring the digest
  # be stored in the session and provided at the response consumption phase.
  #
  # ## Usage
  #
  # OIDC request initiation:
  #
  #   state = OIDC::RelayState.initiate(request_id: id, data: options)
  #   state.digest #=> String for cookie
  #   state.nonce  #=> String for RelayState
  #
  # `Omni-Auth` strategy takes the `nonce` and the request id as the `state` parameter. The
  # `digest` gets stored in the session, retrieved upon consumption (below).
  #
  # SSO response consumption:
  #
  #   state = OIDC::RelayState.consume(nonce: nonce, request_id: id, digest: digest)
  #   state.ok?              #=> Boolean
  #   state.data[:return_to] #=> url String or nil
  #
  class RelayState < ::RelayState
    # Internal: Returns a String key
    def key
      "oidc:relay_state:#{request_id}"
    end
    protected :key
  end
end
