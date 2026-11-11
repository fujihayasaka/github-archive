# frozen_string_literal: true

require "excon"
require "renderer"

module Routes
  module Badges
    class CompatibilityScore < Coach::Middleware
      uses Middlewares::Failbot, route_class: self
      uses Middlewares::CheckParams,
           "dependency-name" => { type: String, required: true },
           "package-manager" => { type: String, required: true },
           "previous-version" => { type: String, required: true },
           "new-version" => { type: String, required: true }

      class BadgenError < StandardError; end

      def call
        return invalid_package_manager_error if invalid_package_manager?

        if request.headers[:Accept] == "application/json"
          Renderer.render(badge_json)
        else
          [
            200,
            {
              "Content-Type" => "image/svg+xml",
              "Cache-Control" => "no-cache",
              "Expires" => 1.minute.from_now,
            },
            [badge_svg],
          ]
        end
      end

      private

      def invalid_package_manager?
        PackageManagers::ALL.exclude?(package_manager)
      end

      def invalid_package_manager_error
        pkg_managers = PackageManagers::ALL.map { |item| "'#{item}'" }
        pkg_managers_text = pkg_managers.to_sentence(
          last_word_connector: " or ",
          two_words_connector: " or ",
        )

        Renderer.render_error(
          status: 400,
          title: "Bad Request",
          detail: "Invalid package manager - must be #{pkg_managers_text}",
        )
      end

      def badge_json
        {
          data: {
            attributes: {
              status: status,
              colour: colour,
              "candidate-updates": candidate_prs_count,
              "successful-updates": ci_success_count,
            },
            type: "compatibility-scores",
          },
        }.to_json
      end

      def badge_svg # rubocop:disable Metrics/MethodLength
        increment_metric
        <<~SVG
            <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="154.1" height="20" viewBox="0 0 1541 200" role="img" aria-label="compatibility: #{status}">
            <title>compatibility: #{status}</title>
            <linearGradient id="UzjqL" x2="0" y2="100%">
              <stop offset="0" stop-opacity=".1" stop-color="#EEE"/>
              <stop offset="1" stop-opacity=".1"/>
            </linearGradient>
            <mask id="XpCPF"><rect width="1541" height="200" rx="30" fill="#FFF"/></mask>
            <g mask="url(#XpCPF)">
              <rect width="939" height="200" fill="#555"/>
              <rect width="602" height="200" fill="#{hex_colour}" x="939"/>
              <rect width="1541" height="200" fill="url(#UzjqL)"/>
            </g>
            <g aria-hidden="true" fill="#fff" text-anchor="start" font-family="Verdana,DejaVu Sans,sans-serif" font-size="110">
              <text x="190" y="148" fill="#000" opacity="0.25">compatibility</text>
              <text x="180" y="138">compatibility</text>
              <text x="80%" y="148" text-anchor="middle" fill="#000" opacity="0.25">#{status}</text>
              <text x="80%" y="138" text-anchor="middle">#{status}</text>
            </g>
            <image x="40" y="35" width="100" height="130" xlink:href="data:image/svg+xml;base64,PHN2ZyBmaWxsPSJub25lIiB2aWV3Qm94PSIwIDAgNTQgNTQiIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyI+PHBhdGggY2xpcC1ydWxlPSJldmVub2RkIiBkPSJNMzAgMTV2LTNoLTVhMSAxIDAgMDEtMS0xVjRhMSAxIDAgMDExLTFoN2ExIDEgMCAwMTEgMXYxMWgxNWEzIDMgMCAwMTMgM3YxMmgyYTEgMSAwIDAxMSAxdjEwYTEgMSAwIDAxLTEgMWgtMnY2YTMgMyAwIDAxLTMgM0g2YTMgMyAwIDAxLTMtM3YtNkgxYTEgMSAwIDAxLTEtMVYzMWExIDEgMCAwMTEtMWgyVjE4YTMgMyAwIDAxMy0zem02Ljg1NCAyMy42NDNsNi4yOS02LjI4OWExLjIxIDEuMjEgMCAwMDAtMS43MWwtMS4yOS0xLjI5YTEuMjEgMS4yMSAwIDAwLTEuNzEgMEwzNS45OTggMzMuNWwtMS42NDUtMS42NDVhMS4yMSAxLjIxIDAgMDAtMS43MSAwbC0xLjI5IDEuMjlhMS4yMSAxLjIxIDAgMDAwIDEuNzFsMy43OSAzLjc5YTEuMjEgMS4yMSAwIDAwMS43MSAwem0tMTMuNzEtNi4yODlsLTYuMjkgNi4yOWExLjIxIDEuMjEgMCAwMS0xLjcxIDBsLTMuNzktMy43OWExLjIxIDEuMjEgMCAwMTAtMS43MWwxLjI5LTEuMjlhMS4yMSAxLjIxIDAgMDExLjcxIDBMMTYgMzMuNWw0LjE0NC00LjE0NWExLjIxIDEuMjEgMCAwMTEuNzExIDBsMS4yOSAxLjI5YTEuMjEgMS4yMSAwIDAxMCAxLjcxeiIgZmlsbD0iI2ZmZiIgZmlsbC1ydWxlPSJldmVub2RkIi8+PC9zdmc+Cg=="/>
          </svg>
        SVG
      end

      def pull_request_counts_cache_key
        "compatibility_score_badge/#{package_manager}/#{dependency_name}/"\
        "#{previous_version}/#{new_version}"
      end

      def subject
        "compatibility"
      end

      def status
        return "unknown" unless candidate_prs_count >= 5

        "#{(percentage_ci_success * 100).round(0)}%"
      end

      def colour
        return "grey" if candidate_prs_count < 5

        percentage_ci_success >= 0.8 ? "green" : "orange"
      end

      def hex_colour
        return grey if candidate_prs_count < 5

        percentage_ci_success >= 0.8 ? green : orange
      end

      def grey
        "#999"
      end

      def orange
        "#F73"
      end

      def green
        "#3C1"
      end

      def percentage_ci_success
        ci_success_count.to_f / candidate_prs_count
      end

      def ci_success_count
        pull_request_counts.fetch(GitHub::CheckRun::Conclusion::SUCCESS, 0)
      end

      def candidate_prs_count
        pull_request_counts.values.sum
      end

      def pull_request_counts
        return @pull_request_counts if defined?(@pull_request_counts)

        if (cached_counts = Rails.cache.fetch(pull_request_counts_cache_key))
          @pull_request_counts = JSON.parse(cached_counts)
          return @pull_request_counts
        end

        @pull_request_counts = ::CompatibilityScore.new(
          dependency_name: dependency_name,
          package_manager: package_manager,
          previous_version: previous_version,
          new_version: new_version,
        ).pull_request_counts

        Rails.cache.write(
          pull_request_counts_cache_key,
          @pull_request_counts.to_json,
          expires_in: pull_request_count_expires_at,
        )

        @pull_request_counts
      end

      def pull_request_count_expires_at
        return 5.minutes if candidate_prs_count < 10
        return 15.minutes if candidate_prs_count < 100
        return 30.minutes if candidate_prs_count < 1000

        60.minutes
      end

      def dependency_name
        params["dependency-name"]
      end

      def package_manager
        params["package-manager"]
      end

      def new_version
        params["new-version"]
      end

      def previous_version
        params["previous-version"]
      end

      def increment_metric
        MetricsClient.increment("compatibility_scores.badges_rendered", tags: {
                                  package_manager: package_manager,
                                  colour: colour,
                                })
      end
    end
  end
end
