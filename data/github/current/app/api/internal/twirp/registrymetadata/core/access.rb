# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Registrymetadata::Core::Access
  # Public: Check the requesting service (client) for the current handler/RPC.
  #
  # service - The Twirp::Service subclass instance.
  # handler - The Api::Internal::Twirp::Handler subclass instance.
  #
  # Returns nothing, or a Permission denied error
  #
  # The Package Registry middleware collects the Authorization, X-Github-Request-ID and Remote-addr headers
  # and populates env with this data, for the handler to use
  def self.call(service, handler, rack_env, env)
    if (auth = rack_env["HTTP_X_TWIRP_AUTHORIZATION"]) && (req_id = rack_env["HTTP_X_GITHUB_REQUEST_ID"])
      real_ip = rack_env["HTTP_X_CLIENT_IP"]
      process(auth, req_id, real_ip, env)
    else
      Twirp::Error.permission_denied("One or more of 'X-Twirp-Authorization' or 'X-Github-Request-Id' headers not provided", {})
    end
  end

  def self.process(authorization, request_id, real_ip, env)
    env[:authorization] = authorization
    env[:request_id] = request_id
    env[:real_ip] = real_ip
    env[:user_agent] = "package_registry"
    env[:path] = "/internal/twirp/github.registrymetadata.core.v1.LoginAPI/ValidateTokenScopes"
  end
end
