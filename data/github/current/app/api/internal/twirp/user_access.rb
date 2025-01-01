# typed: true
# frozen_string_literal: true

# Token-based access restrictions for Twirp services on behalf of a user.
module Api::Internal::Twirp::UserAccess
  # Public: Checks for a user
  # token at the handler instance's request.
  #
  # service - The Twirp::Service subclass instance.
  # handler - The Api::Internal::Twirp::Handler subclass instance.
  #
  # Returns `nil`, but assigns `env[:user_id]` if an authorized user is found.
  # Returns a `Twirp::Error` if a user is required but not present.
  def self.call(service, handler, rack_env, env)
    token_header = rack_env["HTTP_X_TWIRP_AUTHORIZATION"]
    scope_header = rack_env["HTTP_X_TWIRP_SCOPE"]

    if token_header.present? && scope_header.present?
      token = token_header.split(/\s+/).last

      parsed_token = GitHub::Authentication::SignedAuthToken.instrument(
        GitHub::Authentication::SignedAuthToken::Session.verify(token: token, scope: scope_header),
      )

      if parsed_token.present? && parsed_token.valid?
        Failbot.push("gh.user.id": parsed_token.user.id)
        # When the user ID is successfully extracted from the provided authorization
        # header, put it into the Twirp environment and provide a fresh token in a
        # response header.
        env[:user_id] = parsed_token.user.id
      end
    end

    if handler.class.require_user_token? && env[:user_id].blank?
      Twirp::Error.unauthenticated("a valid user token was not provided")
    end
  end
end
