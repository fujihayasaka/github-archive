# typed: true
# frozen_string_literal: true

module GitHub
  class PrivateModeMiddleware

    HEADERS = { "Content-Type" => "text/html" }
    EMPTY_RESPONSE = []

    def self.call(env)
      req = Rack::Request.new(env)
      [valid_private_mode_session?(req.cookies) ? 200 : 403, HEADERS, EMPTY_RESPONSE]
    end

    # Public: Check if request has a valid private mode session.
    #
    # This method should only be used to verify internal nginx requests, not a
    # request directly from a user.
    #
    # If subdomains are enabled, the private_mode_user_session cookie will be
    # used as it should be the only cookie exposed on seperate domains.
    #
    # If subdomains are disabled (running in insecure mode), the user_session
    # itself can be used for simple authentication.
    #
    # This method has no side-effects. Will not cause a Set-Cookie.
    #
    # Returns true or false. Does not handle any user specific permissioning.
    if GitHub.subdomain_private_mode_enabled?
      def self.valid_private_mode_session?(cookies)
        UserSession.authenticate_private_mode(cookies["private_mode_user_session"])
      end
    elsif GitHub.private_mode_enabled?
      def self.valid_private_mode_session?(cookies)
        UserSession.authenticate(cookies["user_session"])
      end
    else
      def self.valid_private_mode_session?(cookies)
        false
      end
    end
  end
end
