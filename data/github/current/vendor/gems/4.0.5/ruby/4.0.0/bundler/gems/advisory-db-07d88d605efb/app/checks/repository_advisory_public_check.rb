# frozen_string_literal: true

# make sure that an advisory review based on a repository advisory can be published
# it can be published when the underlying repository advisory has been published (is not draft)
# it can not be published when the underlying repository advisory is draft
# it is possible to have an advisory review for a repo advisory that is not published when:
# - a cve review for the repo advisory was submitted
# - the cve review was assigned, and notified
# the above creates/updates an advisory review for the underlying ghsa id, even though it could still be draft
class RepositoryAdvisoryPublicCheck
  def self.should_run?(review)
    review.instance_of?(AdvisoryReview)
  end

  def self.execute_check(review:)
    ::GitHub::Telemetry::Logs.logger.debug { "executing #{self.class}" }

    if review.cve_review_feed_entry? && !review.repository_advisory_feed_entry?
      return CheckResult.new(
        status: "failed",
        title: "Advisory Review should not be broadcast",
        summary: "The underlying Repository Advisory #{review.ghsa_id} does not appear to have been published.  There is no feed entry for this advisory.  Therefore, this advisory review should not be broadcast until the underlying Repository Advisory has been published.",
      )
    end

    CheckResult.new(
      status: "passed",
      title: "Advisory Review can be broadcast",
      summary: "This AdvisoryReview is considered safe to be broadcast, since it has feed entries from public sources.",
    )
  end
end
