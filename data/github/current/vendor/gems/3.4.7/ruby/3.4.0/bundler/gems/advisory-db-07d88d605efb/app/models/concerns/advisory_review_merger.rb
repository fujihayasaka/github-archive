# frozen_string_literal: true

module AdvisoryReviewMerger
  # raised when the from advisory has an associated advisory already
  # in such a case, it is too late to easily merge the advisory reviews,
  # since it sould require withdrawing the published advisory
  # right now, this only handles the easier case where the from advisory-review has not been published into an advisory
  AdvisoryAlreadyPublishedError = Class.new(::StandardError)
  AdvisoryNotMergeableError = Class.new(::StandardError)

  # This is a list of feed entry sources which can only be in one, or the other of the reviews being merged
  # To merge an advisory review from NVD, into another advisory review from NVD, does not make sense
  # in such case that would be an advisory review with two CVE IDs
  # Therefore we make sure that such feed entries are not in both reviews before merging
  FeedEntriesWhichCantExistInBoth = [
    NVDImporter.source,
    RepositoryAdvisoriesImporter.source,
  ].to_set.freeze

  # Merge data from the "from_advisory_review" into the "to_advisory_review"
  #
  # This should be used for "overlapping advisory reviews" (see app/jobs/check_for_overlapping_advisory_reviews_job.rb for definition)
  #
  # Merging one advisory review from another does the following:
  # moves all feed entries from the from_advisory_review into the to_advisory_review
  # moves all identifiers, except ghsa_id, from the from_advisory_review into the to_advisory_review
  # comments on both advisory reviews, if they have PRs, informing that a merge happened
  def self.merge_overlapping_advisory_reviews(from_ghsa_id, to_ghsa_id)
    from_advisory_review = AdvisoryReview.find_by! ghsa_id: from_ghsa_id
    to_advisory_review   = AdvisoryReview.find_by! ghsa_id: to_ghsa_id

    # Run a bunch of tests to ensure that merging makes sense and won't cause bad data
    # some of these tests overlap somewhat, but since merging is rare and used in a very specific scenarios its worth being careful
    unless from_advisory_review.may_merge?
      raise AdvisoryNotMergeableError, "Unable to merge advisory review #{from_ghsa_id} because it is not in a mergeable state"
    end

    if from_advisory_review.advisory.present?
      unless from_advisory_review.advisory.withdrawn?
        raise AdvisoryAlreadyPublishedError, "Unable to merge advisory review #{from_ghsa_id} because it has already been published into an advisory"
      end
      if from_advisory_review.advisory.cve_id != from_advisory_review.cve_id
        # defensive coding, it would be odd for an advisory cve id to not match it's advsory review cve id, and if it is happening just don't do the merge
        raise AdvisoryNotMergeableError, "the from Advisory has a CVE ID that does not match it's AdvisoryReview.  This is unexpected and therefore the merge will not be performed."
      end
    end

    # check that feed entries do not overlap in a problematic way
    from_feed_sources = from_advisory_review.feed_entries.pluck(:source).to_set
    to_feed_sources   = to_advisory_review.feed_entries.pluck(:source).to_set
    feed_sources_in_both = from_feed_sources.intersection(to_feed_sources)
    if feed_sources_in_both.intersect?(FeedEntriesWhichCantExistInBoth)
      raise AdvisoryNotMergeableError, "Unable to merge advisory review #{from_ghsa_id} because it has feed entries from sources that are also in #{to_ghsa_id}"
    end

    AdvisoryReview.transaction do
      from_advisory_review.feed_entries.each do |feed_entry|
        feed_entry.advisory_review = to_advisory_review
        feed_entry.save!
      end

      if from_advisory_review.cve_id.present?
        to_advisory_review.cve_id = from_advisory_review.cve_id
        from_advisory_review.cve_id = nil
      end

      if from_advisory_review.advisory.present? && from_advisory_review.advisory.cve_id.present?
        from_advisory_review.advisory.update!(cve_id: nil)
      end

      from_advisory_review.save!
      to_advisory_review.save!
    end

    # close the from advisory review
    from_advisory_review.merge!
    to_advisory_review.apply_blocklist
  end
end
