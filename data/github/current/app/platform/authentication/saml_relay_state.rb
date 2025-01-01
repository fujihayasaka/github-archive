# typed: true
# frozen_string_literal: true

require "relay_state"

module Platform
  module Authentication
    # A class to manage SAML request/response relay state.
    #
    # Provides an opaque token for use as the `RelayState` during `AuthnRequest`
    # phase and consumed along with the `SAMLResponse` in the response phase.
    #
    # It is designed to persist state like the `return_to` URL.
    #
    # It also verifies the integrity of the relay state by requiring the digest
    # be stored in the session and provided at the response consumption phase.
    #
    # ## Usage
    #
    # SSO request initiation:
    #
    #   state = SamlRelayState.initiate(request_id: id, data:{return_to: url})
    #   state.digest #=> String for cookie
    #   state.nonce  #=> String for RelayState
    #
    # `SamlAuthnRequestUrl` takes the `nonce` as the `relay_state` kwarg. The
    # `digest` gets stored in the session, retrieved upon consumption (below).
    #
    # SSO response consumption:
    #
    #   state = SamlRelayState.consume(nonce: nonce, request_id: id, digest: digest)
    #   state.ok?              #=> Boolean
    #   state.data[:return_to] #=> url String or nil
    #
    class SamlRelayState < ::RelayState
      DEFAULT_EXPIRY = RelayState::DEFAULT_EXPIRY

      # Internal: Returns a String key
      def key
        "saml:relay_state:#{nonce}"
      end
      protected :key
    end
  end
end
