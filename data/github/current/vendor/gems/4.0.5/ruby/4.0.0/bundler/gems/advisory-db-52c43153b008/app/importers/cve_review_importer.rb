# frozen_string_literal: true

# turn an assigned cve review into an advisory review
# this is intended to be used when an assigned CVE Review is notified
# thus the advisory review for the ghsa will always have the assigned cve id set
class CVEReviewImporter < ApplicationImporter
  NotImportableError = Class.new(StandardError)

  disable_auto_import

  attr_reader :cve_review

  def initialize(cve_review_id:)
    @cve_review = CVEReview.find(cve_review_id)

    return if cve_review.importable?

    raise NotImportableError, "CVE Review #{cve_review.ghsa_id} is not importable"
  end

  def each(&)
    [cve_review.importer_object].each(&)
  end
end
