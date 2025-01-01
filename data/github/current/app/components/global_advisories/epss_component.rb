# typed: true
# frozen_string_literal: true

module GlobalAdvisories
  class EPSSComponent < ApplicationComponent

    attr_reader :vulnerability, :cve_epss

    def initialize(vulnerability, cve_epss)
      @vulnerability = vulnerability
      @cve_epss = cve_epss
    end

    private

    def epss_percentage
      percentage = cve_epss.percentage.round(6) * 100
      return "< 0.001%" if percentage < 0.001
      number_to_percentage(percentage, precision: 5, strip_insignificant_zeros: true)
    end

    def epss_percentile
      "(#{(cve_epss.percentile.round(6) * 100).round.ordinalize} percentile)"
    end

    def title
      "Exploit Prediction Scoring System (EPSS)"
    end
  end
end
