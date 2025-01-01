# typed: true
# frozen_string_literal: true

require "cvss_suite"

module AdvisoryDB
  module CvssScore
    def cvss_v3_score
      score_from_cvss(cvss_v3)
    end

    def cvss_v4_score
      score_from_cvss(cvss_v4)
    end

    def parse_cvss(vector_string)
      CvssSuite.new(vector_string)
    end

    def score_from_cvss(vector_string)
      score_from_parsed_cvss(parse_cvss(vector_string))
    end

    def score_from_parsed_cvss(parsed_cvss)
      parsed_cvss.valid? ? parsed_cvss.overall_score : 0.0
    end

    def severity_from_cvss(vector_string)
      severity_from_parsed_cvss(parse_cvss(vector_string))
    end

    def severity_from_parsed_cvss(parsed_cvss)
      return unless parsed_cvss.valid?

      severity = parsed_cvss.severity.downcase
      # The severities from the gem match the ones from GitHub,
      # except for the gem labels None and Moderate.
      case severity
      when "none" then "low"
      when "medium" then "moderate"
      else
        severity
      end
    end
  end
end
