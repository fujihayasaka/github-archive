# frozen_string_literal: true

class SupportedEcosystemCheck
  def self.should_run?(review)
    review.instance_of?(AdvisoryReview)
  end

  def self.execute_check(review:)
    ::GitHub::Telemetry::Logs.logger.debug { "executing #{self.class}" }

    ecosystems =
      begin
        review.advisory_payload["vulnerabilities"].each_value.reject { |v| v["withdrawn"] }.map { |v| v["ecosystem"] }.uniq
      rescue NoMethodError, TypeError
        []
      end

    if ecosystems.empty?
      return CheckResult.new(
        status: "failed",
        title: "Advisory file not in expected structure",
        summary: "Failed to find any ecosystem keys in vunlnerability packages",
      )
    end

    ecosystems.each do |ecosystem|
      unless AdvisoryDB.curator_publishable_ecosystems.include?(ecosystem)
        return CheckResult.new(
          status: "failed",
          title: "Unsupported ecosystem found",
          summary: <<-SUMMARY,
            #{ecosystem} is currently unsupported.
            You can still save and update the advisory review with this ecosystem, but it cannot be published.
          SUMMARY
        )
      end

      if ecosystem == "other" && review.source_code_location.blank?
        return CheckResult.new(
          status: "failed",
          title: "Other ecosystem",
          summary: "source code's location must be provided to use other as an ecosystem.",
        )
      end
    end

    CheckResult.new(
      status: "passed",
      title: "Supported ecosystem",
      summary: "#{ecosystems.join(", ")} #{"is".pluralize(ecosystems.length)} supported and can be published",
    )
  end
end
