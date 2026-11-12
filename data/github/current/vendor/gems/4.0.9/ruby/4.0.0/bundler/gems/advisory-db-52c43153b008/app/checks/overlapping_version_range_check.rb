# frozen_string_literal: true

require "advisory_db/vulnerability_validator"

# A check to ensure:
# - No two vulnerability version ranges overlap
# - No vulnerability version range contains a patched version
class OverlappingVersionRangeCheck
  def self.should_run?(review)
    review.instance_of?(AdvisoryReview)
  end

  def self.execute_check(review:)
    ::GitHub::Telemetry::Logs.logger.debug { "executing #{self.class}" }
    vulnerabilities = AdvisoryDB::VulnerabilityValidator.parse_from_advisory(review.advisory_payload)
    result = compare_vulnerabilities(vulnerabilities)

    CheckResult.new(**result)
  rescue NoMethodError, TypeError => error
    CheckResult.new(status: "failed", title: "Advisory file not in expected structure", summary: error.message)
  end

  # Compare each VulnerabilityComparator instace against each other
  # Marks the check as failed if `#compare` returns false
  def self.compare_vulnerabilities(vulnerabilities)
    result = { status: "passed", title: "", summary: "" }

    vulnerabilities.combination(2).each do |primary, secondary|
      next unless primary.overlap?(secondary) || secondary.overlap?(primary)

      result[:status] = "failed"
      result[:title] = "Vulnerable version range overlap"
      result[:summary] += primary.overlap_errors.full_messages.join("\n")
      result[:summary] += secondary.overlap_errors.full_messages.join("\n")
    end

    result
  end
end
