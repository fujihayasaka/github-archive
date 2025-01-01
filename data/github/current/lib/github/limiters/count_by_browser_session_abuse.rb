# typed: true
# frozen_string_literal: true

module GitHub
  module Limiters
    # Limit requests based on browser session from the _gh_sess cookie.
    # This will uniquely identify browser sessions, authenticated or not.
    # This limit is higher than CountByBrowserSession and does NOT
    # skip when referer matches.
    class CountByBrowserSessionAbuse < CountByBrowserSession
      OTHER_IGNORED_PATHS_INCLUDE_SHELF = %r(/notifications/beta/shelf|/partials/deployed_event/|/projects/\d+/cards/)
      OTHER_IGNORED_PATHS = %r(/partials/deployed_event/|/projects/\d+/cards/)

      def start(request)
        if FeatureFlag.vexi.enabled_or_raise?(:remove_shelf_limited_paths) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
          return OK if OTHER_IGNORED_PATHS.match?(request.path_info)
        else
          return OK if OTHER_IGNORED_PATHS_INCLUDE_SHELF.match?(request.path_info)
        end
        super
      end

      # Should the limiter skip counting requests from the same host?
      def skip_same_origin_referer?
        false
      end
    end
  end
end
