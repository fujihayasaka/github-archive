# typed: true
# frozen_string_literal: true

module GlobalAdvisories
  class EPSSComponent < ApplicationComponent

    TOOLTIP_DEFINITION = "This score estimates the probability of this vulnerability being exploited within the next 30 days. Data is provided by FIRST.org."
    attr_reader :vulnerability, :cve_epss

    def initialize(vulnerability, cve_epss)
      @vulnerability = vulnerability
      @cve_epss = cve_epss
    end

    private

    def epss_percentage
      number_to_percentage(cve_epss.percentage.round(6) * 100)
    end

    def epss_percentile
      "(" + (cve_epss.percentile.round(6) * 100).round.ordinalize + " percentile)"
    end

    def epss_tooltip
      TOOLTIP_DEFINITION
    end
  end
end
