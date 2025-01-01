# frozen_string_literal: true

class ApplyBlocklistJob < ApplicationJob
  queue_as :default

  def perform(advisory_review_ids: nil, blocklisted_term_ids: nil)
    advisory_reviews = AdvisoryReview.all
    advisory_reviews = advisory_reviews.where(id: advisory_review_ids) if advisory_review_ids

    blocklisted_terms = BlocklistedTerm.all
    blocklisted_terms = blocklisted_terms.where(id: blocklisted_term_ids) if blocklisted_term_ids
    blocklisted_terms = blocklisted_terms.to_a # Load into memory only once

    advisory_reviews.apply_blocklist(blocklisted_terms: blocklisted_terms)
  end
end
