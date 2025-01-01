# frozen_string_literal: true

class CVEReviewPublishableCheck
  def self.should_run?(review)
    review.instance_of?(CVEReview)
  end

  def self.execute_check(review:)
    ::GitHub::Telemetry::Logs.logger.debug { "executing #{self.class}" }

    unless review.valid?
      return CheckResult.new(
        status: "failed",
        title: "CVE Review is invalid",
        summary: PP.pp(review.errors.details, +"").chomp,
      )
    end

    unless review.assigned?
      return CheckResult.new(
        status: "failed",
        title: "CVE Review must be assigned a CVE to be publishable",
        summary: "",
      )
    end

    errs = review.notification_errors
    unless errs.empty?
      return CheckResult.new(
        status: "failed",
        title: "CVE Review can not be published",
        summary: errs.join("\n"),
      )
    end

    review.reload

    CheckResult.new(
      status: "passed",
      title: "CVE Review is publishable",
      summary: "",
    )
  end
end
