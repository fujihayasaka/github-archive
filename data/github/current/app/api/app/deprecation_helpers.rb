# typed: false
# frozen_string_literal: true

module Api
  class App
    module DeprecationHelpers
      # https://tools.ietf.org/html/rfc8594
      SUNSET_HEADER = "Sunset"

      # https://tools.ietf.org/html/draft-dalal-deprecation-header-02
      DEPRECATION_HEADER = "Deprecation"
      DEPRECATION_LINK_RELATION = "deprecation"

      ALTERNATE_RELATION = "alternate"

      def set_deprecation_headers!
        route_deprecation = request.env[GitHub::Routers::Api::DEPRECATED_ROUTE]

        if route_deprecation
          route_deprecation[:alternate_path_url] = request.env[GitHub::Routers::Api::PATH_INFO]
        end

        # A resource may be deprecated by route (Through Routers::API)
        # or by marking the resource deprecated (deprecation_dependency.rb)
        deprecation_details = @deprecated || route_deprecation

        # Only adding headers and link relations on GitHub.com at the moment.
        # For enterprise, we will want to link to the next version and use
        # the enterprise release dates.
        return unless GitHub.api_deprecation_headers_enabled? && deprecation_details

        # Add the `Deprecation` and `Sunset` Headers
        headers[DEPRECATION_HEADER] = deprecation_details[:deprecation_date].httpdate
        headers[SUNSET_HEADER] = deprecation_details[:sunset_date].httpdate

        # And a Link relation to a blog post / page describing the deprecation
        @links.add(deprecation_details[:info_url], rel: DEPRECATION_LINK_RELATION, type: "text/html")

        # If an alternative resource is available, link to it using the
        # `alternate` link relation.
        if alternate_path = deprecation_details[:alternate_path_url]
          absolute_alternate_url = api_url(alternate_path)
          @links.add(absolute_alternate_url, rel: ALTERNATE_RELATION)
        end
      end
    end
  end
end
