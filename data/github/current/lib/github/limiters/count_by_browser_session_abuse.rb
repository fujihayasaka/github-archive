# typed: true
# frozen_string_literal: true

module GitHub
  module Limiters
    # Limit requests based on browser session from the _gh_sess cookie.
    # This will uniquely identify browser sessions, authenticated or not.
    # This limit is higher than CountByBrowserSession and does NOT
    # skip when referer matches.
    class CountByBrowserSessionAbuse < CountByBrowserSession
      OTHER_IGNORED_PATHS = %r(/notifications/beta/shelf|/partials/deployed_event/|/projects/\d+/cards/)

      def start(request)
        return OK if OTHER_IGNORED_PATHS.match(request.path_info)
        super
      end

      # Should the limiter skip counting requests from the same host?
      def skip_same_origin_referer?
        false
      end
    end
  end
end
