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
        @api_versions = versions.sort_by { |v| Date.iso8601(v) }.reverse
      end
    end
  end

  extend Config::ApiVersioning
end
