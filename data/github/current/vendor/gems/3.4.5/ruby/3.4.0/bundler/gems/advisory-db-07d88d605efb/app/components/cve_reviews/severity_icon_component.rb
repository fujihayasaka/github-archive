# frozen_string_literal: true

module CVEReviews
  class SeverityIconComponent < ApplicationComponent
    attr_reader :severity, :label_args

    SEVERITY_SCHEMES = {
      "low" => :primary,
      "moderate" => :warning,
      "high" => :severe,
      "critical" => :danger,
    }.freeze

    def initialize(severity:, **label_args)
      @severity = severity
      @label_args = label_args
    end

    def severity_scheme(severity)
      SEVERITY_SCHEMES[severity]
    end

    def render?
      severity.present?
    end
  end
end
