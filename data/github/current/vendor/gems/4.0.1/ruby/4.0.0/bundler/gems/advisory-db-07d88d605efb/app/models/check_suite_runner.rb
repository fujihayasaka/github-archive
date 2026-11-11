# frozen_string_literal: true

module CheckSuiteRunner
  extend self

  # Order matches the appearance of the form
  CHECK_CLASSES = [
    # CVE Review only
    CVEReviewPublishableCheck,
    MITREJSONCheck,
    # Advisory review only
    SupportedEcosystemCheck,
    OverlappingVersionRangeCheck,
    UnusualVersionRangeCheck,
    MatchingSeverityCheck,
    RepositoryAdvisoryPublicCheck,
    SimulatedPublicationCheck,
    # both
    ReferencesCheck,
  ].freeze

  def checks_passed?(review:)
    get_checks(review: review).all? { |check| check["status"] == "passed" || check["status"] == "warning" }
  end

  def get_checks(review:)
    checks_for_review(review).map do |check_class|
      JSON.parse(AdvisoryDB.redis.get("#{review.class}:#{review.ghsa_id}:#{check_class}") || "{}").merge("check_class" => check_class)
    end
  end

  # async option not currently in-use, but benchmarking runs might indicate that the suite should be non-blocking for page load
  def run_checks(review:, async: false)
    checks_for_review(review).each do |check_class|
      update_check_status(check_class: check_class, review: review, status: "queued")
      if async
        ExecuteInboxCheckJob.perform_later(check_class_name: check_class.name, review: review)
      else
        AdvisoryDB.stats.time("review_check.time", tags: AdvisoryDB.dogtags(check_class: check_class.name)) do
          ExecuteInboxCheckJob.perform_now(check_class_name: check_class.name, review: review)
        end
      end
    end
  end

  def update_check_status(check_class:, review:, status:, message: nil)
    AdvisoryDB.redis.set(
      "#{review.class}:#{review.ghsa_id}:#{check_class}",
      { status: status, message: message }.to_json,
    )
  end

  private

  def checks_for_review(review)
    CHECK_CLASSES.select { |check_class| check_class.should_run?(review) }
  end
end
