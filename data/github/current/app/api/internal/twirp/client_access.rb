# typed: true
# frozen_string_literal: true

# Simple HMAC-based service-to-service access control.
#
# Note: this is a stopgap measure until we have better ways to identify services.
module Api::Internal::Twirp::ClientAccess
  # Convenient client names used for testing
  TEST_CLIENT_NAMES = %w(allowed otherallowed disallowed)

  # Public: Check the requesting service (client)
  # for the current handler/RPC.
  #
  # service - The Twirp::Service subclass instance.
  # handler - The Api::Internal::Twirp::Handler subclass instance.
  #
  # Returns `nil` in case of success, or a `Twirp::Error`
  def self.call(service, handler, rack_env, env)
    if (client_key = rack_env[:request_hmac_key])
      client_name = GitHub.api_internal_twirp_hmac_settings[client_key]
      Failbot.push("peer.service": client_name)
      allow_client = (
        # In test, support some special clients:
        (GitHub.twirp_supports_test_clients? && TEST_CLIENT_NAMES.include?(client_name) && client_name == "allowed") ||
        # Usually, fall back to calling the handler:
        handler.allow_client?(client_name, env)
      )

      if !allow_client
        Twirp::Error.permission_denied("client not supported", name: client_name)
      end
    else
      # It shouldn't be possible to reach this point, but we return a Twirp
      # error just in case.
      Twirp::Error.permission_denied("a valid request HMAC was not provided", {})
    end
  end
end
