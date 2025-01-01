# frozen_string_literal: true

require "advisory_db/vulnerability_validator"

# A check to ensure:
# - Vulnerable version range does not contain patched version
# - Vulnerable version range is lower than patched version
# - Vulnerable version range has correct upper and lower versions
# - Vulnerable version range does not have infinite floor version
class UnusualVersionRangeCheck
  def self.should_run?(review)
    review.instance_of?(AdvisoryReview)
  end

  def self.execute_check(review:)
    ::GitHub::Telemetry::Logs.logger.debug { "executing #{self.class}" }
    vulnerabilities = AdvisoryDB::VulnerabilityValidator.parse_from_advisory(review.advisory_payload)
    result = validate_vulnerabilities(vulnerabilities)

    CheckResult.new(**result)
  rescue NoMethodError, TypeError => error
    CheckResult.new(status: "failed", title: "Advisory file not in expected structure", summary: error.message)
  end

  # Validates each vulnerability
  def self.validate_vulnerabilities(vulnerabilities)
    result = { status: "passed", title: "Version ranges look reasonable", summary: "" }

    vulnerabilities.each do |vuln|
      next if vuln.valid?

      result[:status] = "failed"
      result[:title] = "One or more versions ranges do not look reasonable"
      result[:summary] += vuln.errors.full_messages.join("\n")
    end

    result
  end
end
