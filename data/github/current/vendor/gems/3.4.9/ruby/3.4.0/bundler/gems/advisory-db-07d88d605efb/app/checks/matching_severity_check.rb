# frozen_string_literal: true

class MatchingSeverityCheck
  def self.should_run?(review)
    review.instance_of?(AdvisoryReview)
  end

  def self.execute_check(review:)
    ::GitHub::Telemetry::Logs.logger.debug { "executing #{self.class}" }

    cvss_v3 = review.advisory_payload["cvss_v3"]
    cvss_v4 = review.advisory_payload["cvss_v4"]
    severity = review.advisory_payload["severity"]
    cvss_v4_severity = cvss_v4.present? ? SeverityCalculator.from_cvss_v4(cvss_v4) : ""
    cvss_v3_severity = cvss_v3.present? ? SeverityCalculator.from_cvss_v3(cvss_v3) : ""

    if cvss_v4_severity.present?
      if severity.present? && (cvss_v4_severity != severity)
        failed_result_summary = "CVSS 4 severity \"#{cvss_v4_severity}\" does not match severity \"#{severity}\""
      elsif severity.present? && (cvss_v4_severity == severity)
        passed_result_summary = "CVSS 4 severity \"#{cvss_v4_severity}\" matches severity \"#{severity}\""
      end
    elsif cvss_v3_severity.present?
      if severity.present? && (cvss_v3_severity != severity)
        failed_result_summary = "CVSS 3 severity \"#{cvss_v3_severity}\" does not match severity \"#{severity}\""
      elsif severity.present? && (cvss_v3_severity == severity)
        passed_result_summary = "CVSS 3 severity \"#{cvss_v3_severity}\" matches severity \"#{severity}\""
      end
    end

    if failed_result_summary.present?
      return CheckResult.new(
        status: "failed",
        title: "CVSS and severity mismatch",
        summary: failed_result_summary,
      )
    elsif passed_result_summary.present?
      return CheckResult.new(
        status: "passed",
        title: "Severity matches",
        summary: passed_result_summary,
      )
    end

    if (cvss_v3_severity.present? || cvss_v4_severity.present?) && severity.blank?
      CheckResult.new(
        status: "passed",
        title: "CVSS is present but no severity is present.",
        summary: "Please set the severity if applicable.",
      )
    elsif severity.present?
      CheckResult.new(
        status: "passed",
        title: "No CVSS present, using severity",
        summary: "Severity is \"#{severity}\"",
      )
    else
      CheckResult.new(
        status: "passed",
        title: "No CVSS or severity present",
        summary: "Nothing to compare",
      )
    end
  end
end
