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
      API_VERSIONS_DOCS_URL = "https://docs.github.com/en/rest/about-the-rest-api/api-versions"

      ALTERNATE_RELATION = "alternate"

      def set_deprecation_headers!
        route_deprecation = request.env[GitHub::Routers::Api::DEPRECATED_ROUTE]

        if route_deprecation
          route_deprecation[:alternate_path_url] = request.env[GitHub::Routers::Api::PATH_INFO]
        end

        # A resource may be deprecated by route (Through Routers::API)
        # or by marking the resource deprecated (deprecation_dependency.rb)
        deprecation_details = @deprecated || route_deprecation || deprecation_details_from_operation_changeset

        # Only adding headers and link relations on GitHub.com at the moment.
        # For enterprise, we will want to link to the next version and use
        # the enterprise release dates.
        return unless GitHub.api_deprecation_headers_enabled? && deprecation_details

        # Add the `Deprecation` and `Sunset` Headers
        sunset_date = compute_sunset_date(deprecation_details)
        return unless deprecation_details[:deprecation_date] && sunset_date

        headers[DEPRECATION_HEADER] = deprecation_details[:deprecation_date].httpdate
        headers[SUNSET_HEADER] = sunset_date.httpdate

        # And a Link relation to a blog post / page describing the deprecation.
        # Use info_url if provided (non-nil, even if empty), or fall back to API versions docs.
        if deprecation_details[:info_url].nil?
          # No info_url provided: fall back to API versions docs
          @links.add(API_VERSIONS_DOCS_URL, rel: DEPRECATION_LINK_RELATION, type: "text/html")
        else
          # info_url provided (could be empty string or a URL)
          @links.add(deprecation_details[:info_url], rel: DEPRECATION_LINK_RELATION, type: "text/html")
        end

        # If an alternative resource is available, link to it using the
        # `alternate` link relation.
        if alternate_path = deprecation_details[:alternate_path_url]
          absolute_alternate_url = api_url(alternate_path)
          @links.add(absolute_alternate_url, rel: ALTERNATE_RELATION)
        end
      end

      private

      # Builds deprecation details derived from the operation's published changesets,
      # used as a fallback when no explicit deprecated() or deprecated_route! declaration
      # exists on the endpoint.
      #
      # Returns nil (and emits no headers) when:
      #   - The client sent X-GitHub-Api-Version on or after the changeset date
      #   - No changesets have been promoted to a published version (e.g. all are :next)
      def deprecation_details_from_operation_changeset
        return unless requested_api_version_before_changeset?

        deprecation_date = deprecation_from_operation_changeset
        return unless deprecation_date

        # Always provide info_url for changeset-derived deprecation, defaulting to API versions docs
        {
          deprecation_date: deprecation_date,
          info_url: API_VERSIONS_DOCS_URL,
        }
      end

      # Returns true unless the client explicitly provided X-GitHub-Api-Version
      # and the requested date is on or after the earliest published changeset date.
      # Clients with no version header (or a nil version) are always warned.
      def requested_api_version_before_changeset?
        return true unless @selected_api_version&.request_header?

        requested_version = @selected_api_version.version.to_s
        return false if requested_version == "next"

        requested_date = Date.parse(requested_version)
        earliest_changeset_date = operation_changeset_version_dates.min
        return true unless earliest_changeset_date.is_a?(Date)

        requested_date < earliest_changeset_date
      rescue Date::Error, ArgumentError, TypeError
        true
      end

      # Resolves the sunset date for the Sunset response header (RFC 8594).
      #
      # Prefers an explicitly provided sunset_date in deprecation_details,
      # allowing manual override when needed. Falls back to calculating
      # 2 years after the version date of the operation's earliest versioned
      # changeset linked via x-github-breaking-changes. This ties the sunset
      # window to when the breaking change officially shipped in the API
      # versioning system.
      def compute_sunset_date(deprecation_details)
        deprecation_details[:sunset_date] || sunset_from_operation_changeset
      end

      def deprecation_from_operation_changeset
        operation_changeset_version_dates.min
      end

      # Returns a Date 2 years after the earliest versioned changeset linked to
      # the current operation, or nil if no such changeset exists.
      def sunset_from_operation_changeset
        deprecation_from_operation_changeset&.advance(years: 2)
      end

      # Collects the published version dates for all changesets linked to the current
      # operation via x-github-breaking-changes. Changesets that have not yet been
      # promoted to a calendar version (i.e. version is the :next symbol) are excluded.
      #
      # Returns an Array of Date objects, which may be empty.
      def operation_changeset_version_dates
        return [] unless @operation

        breaking_changes = @operation.raw["x-github-breaking-changes"]
        return [] unless breaking_changes&.any?

        schedule = ::OpenApi::Description::Changeset.schedule
        breaking_changes.filter_map do |change|
          version = schedule.changeset_version(changeset: change["changeset"])
          next unless version.is_a?(String)

          begin
            Date.parse(version)
          rescue Date::Error
            nil
          end
        end
      end
    end
  end
end
