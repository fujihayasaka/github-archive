# frozen_string_literal: true

module AdvisoryReviews
  class EPSSComponent < ApplicationComponent
    attr_reader :ghsa_id

    def initialize(ghsa_id:)
      @ghsa_id = ghsa_id
    end

    def epss_data?
      # We'd check keys, except Sawyer::Resources don't support it.
      epss_data.present? && epss_data[:percentage].present? && epss_data[:percentile].present?
    end

    def epss_percentage
      number_to_percentage(epss_data["percentage"].round(6) * 100)
    end

    def epss_percentile
      "#{(epss_data["percentile"].round(6) * 100).round.ordinalize} percentile"
    end

    def epss_data
      return @epss_data if defined? @epss_data

      if Rails.env.development?
        @epss_data = { "percentage" => 0.83451, "percentile" => 0.13456 }.with_indifferent_access
      else
        advisory_data_from_dotcom = AdvisoryDB.github.get("/advisories/#{@ghsa_id}")
        @epss_data = advisory_data_from_dotcom[:epss] || {}
      end

      @epss_data
    rescue Octokit::ClientError, Faraday::ConnectionFailed => error
      ::GitHub::Telemetry::Logs.logger.error(
        "Error occurred while executing request against GitHub API to fetch EPSS for GHSA.",
        {
          exception: error,
          "gh.ghsa_id": @ghsa_id,
        },
      )
      @epss_error = error
      @epss_data = {}
    end

    def epss_error?
      epss_error.present?
    end

    def epss_error
      @epss_error.to_s
    end
  end
end
