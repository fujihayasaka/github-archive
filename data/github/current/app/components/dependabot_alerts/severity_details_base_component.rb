# typed: true
# frozen_string_literal: true

# rubocop:disable ViewComponent/ComponentsHaveUnitTests
module DependabotAlerts
  class SeverityDetailsBaseComponent < ApplicationComponent
    include AdvisoryDB::CvssScore

    OVERALL_SCORE_DEFINITION = "This score calculates overall vulnerability severity from 0 to 10 and is based on the Common Vulnerability Scoring System (CVSS)."

    attr_reader :cvss_vector

    def initialize(cvss_vector: nil, severity: nil)
      @cvss_vector = cvss_vector.presence
      @severity = severity.presence&.downcase
    end

    def before_render
      if severities_conflict?
        GitHub.logger.info(
          "Given severity conflicts with CVSS severity",
          "code.namespace": self.class.name,
          "gh.security_alerts.severity": severity,
          "gh.security_alerts.cvss_severity": cvss_severity,
          "gh.security_alerts.cvss_vector": cvss_vector,
        )
      end
    end

    memoize def severity
      @severity || cvss_severity
    end

    def show_metrics?
      cvss.valid? && !severities_conflict?
    end

    def cvss_overall_score
      cvss.overall_score.to_s
    end

    def definition_for_cvss_overall_score
      OVERALL_SCORE_DEFINITION
    end

    def value_for_metric(metric)
      cvss.base.public_send(metric)&.selected_value&.dig(:name) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
    end

    def test_selector_for_metric(metric)
      "#{metric.to_s.dasherize}-value"
    end

    private

    memoize def cvss
      parse_cvss(cvss_vector)
    end

    def cvss_severity
      severity_from_parsed_cvss(cvss)
    end

    def severities_conflict?
      cvss_severity && (severity != cvss_severity)
    end
  end
end
