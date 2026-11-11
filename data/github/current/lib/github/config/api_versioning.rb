# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module ApiVersioning
      # Retrieve the list of currently supported API versions.
      #
      # @return [Array<String>]
      def api_versions
        @api_versions ||= []
      end

      # Set the list of currently supported API versions.
      #
      # @param versions [Array<String>] API versions; these are ISO 8601
      #   formatted dates (YYYY-MM-DD) and should be in descending order so that
      #   the most recent version is first.
      #
      # @example
      #
      #   GitHub.api_versions = %w[
      #     2022-01-01
      #     2021-10-01
      #   ]
      #
      # @return [Array<String>]
      def api_versions=(versions)
        @api_versions = normalize_api_versions(versions)
      end

      # Retrieve the list of explicitly unsupported API versions.
      #
      # @return [Array<String>]
      def unsupported_api_versions
        @unsupported_api_versions ||= []
      end

      # Set the list of explicitly unsupported API versions.
      #
      # @param versions [Array<String>] API versions; these are ISO 8601
      #   formatted dates (YYYY-MM-DD) and should be in descending order so that
      #   the most recent version is first.
      #
      # @return [Array<String>]
      def unsupported_api_versions=(versions)
        @unsupported_api_versions = normalize_api_versions(versions)
      end

      # Retrieve the configured deprecation dates for supported API versions.
      #
      # @return [Hash{String => String}]
      def api_version_deprecation_dates
        @api_version_deprecation_dates ||= {}
      end

      # Set the configured deprecation dates for supported API versions.
      #
      # @param dates [Hash{String => String}] A mapping of API versions to
      #   ISO 8601 formatted deprecation dates.
      #
      # @return [Hash{String => String}]
      def api_version_deprecation_dates=(dates)
        @api_version_deprecation_dates = normalize_api_version_deprecation_dates(dates)
      end

      private

      def normalize_api_versions(versions)
        versions.sort_by { |version| Date.iso8601(version) }.reverse
      end

      def normalize_api_version_deprecation_dates(dates)
        dates
          .to_h
          .map { |version, deprecation_date| [Date.iso8601(version).iso8601, Date.iso8601(deprecation_date).iso8601] }
          .sort_by { |version, _| Date.iso8601(version) }
          .reverse
          .to_h
      end
    end
  end

  extend Config::ApiVersioning
end
