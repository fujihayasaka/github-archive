# frozen_string_literal: true

class MITREJSONCheck
  def self.should_run?(review)
    review.instance_of?(CVEReview)
  end

  def self.execute_check(review:)
    ::GitHub::Telemetry::Logs.logger.debug { "executing #{self.class}" }

    json_builder = review.cve_json_builder

    if json_builder.invalid?
      return CheckResult.new(
        status: "failed",
        title: "JSON is not MITRE-compatible",
        summary: json_builder.errors.full_messages.map { |err| err.prepend("- ") }.join("\n"),
      )
    end

    CheckResult.new(
      status: "passed",
      title: "JSON is MITRE-compatible",
      summary: "",
    )
  end
end
