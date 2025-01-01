# typed: true
# frozen_string_literal: true

module Codespaces
  class FollowVsoRedirects < FaradayMiddleware::FollowRedirects
    ALLOWED_REDIRECT_ORIGIN = "visualstudio.com"

    # By default FollowRedirects only includes the Authorization header iff it's
    # being redirected to the same host as the original request. But in our case,
    # it's *also* OK to include if we're redirecting to a subdomain of the
    # original host or any subdomain of 'visualstudio.com' since that'd be a
    # specific Azure AZ.
    def redirect_to_same_host?(from_url, to_url)
      return true if super(from_url, to_url)

      to_uri = URI.parse(to_url)
      to_host = to_uri.host
      # Expressly allow redirects to 'visualstudio.com'
      return true if to_host == ALLOWED_REDIRECT_ORIGIN

      # Check for subdomains of the original host or 'visualstudio.com' by prepending them with a dot before checking
      # `end_with?`
      from_uri = URI.parse(from_url)
      from_host = from_uri.host
      !!to_host&.end_with?(".#{from_host}", ".#{ALLOWED_REDIRECT_ORIGIN}")
    end
  end
end
