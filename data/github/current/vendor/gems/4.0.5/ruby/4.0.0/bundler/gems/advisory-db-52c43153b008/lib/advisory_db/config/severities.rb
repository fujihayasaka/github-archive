# frozen_string_literal: true

module AdvisoryDB
  module Config
    module Severities
      # WARNING: It's important that this array is kept in order from least to
      # most severe, and that new severities are added to the end of the array.
      # This means that unless a new severity is introduced that is more severe
      # than "critical," this array should not be updated.
      SEVERITIES = %w[
        low
        moderate
        high
        critical
      ].freeze

      SEVERITY_LABELS = {
        "low" => "Low",
        "moderate" => "Moderate",
        "high" => "High",
        "critical" => "Critical",
      }.freeze

      SEVERITY_COLORS = {
        "low" => "2f363d",
        "moderate" => "b08800",
        "high" => "c24e00",
        "critical" => "9e1c23",
      }.freeze

      SEVERITY_SCHEMES = {
        "low" => :default,
        "moderate" => :attention,
        "high" => :severe,
        "critical" => :danger,
      }.freeze

      def severities
        SEVERITIES
      end

      def severity_label(severity)
        return "Not Assigned" if severity.nil?

        SEVERITY_LABELS.fetch(severity) { severity.humanize }
      end

      def severity_color(severity)
        # The fallback is Primer's default gray.
        # See: https://primer.style/css/support/color-system
        SEVERITY_COLORS.fetch(severity, "6a737d")
      end

      def severity_scheme(severity)
        SEVERITY_SCHEMES.fetch(severity, :muted)
      end
    end

    include Severities
  end
end
