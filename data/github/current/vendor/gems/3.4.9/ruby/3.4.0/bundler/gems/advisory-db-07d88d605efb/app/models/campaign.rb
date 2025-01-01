# frozen_string_literal: true

class Campaign < ApplicationRecord
  STATUSES = ["active", "complete"].freeze

  has_many :advisory_reviews_campaigns, autosave: true, dependent: :delete_all
  has_many :advisory_reviews, through: :advisory_reviews_campaigns

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :advisory_reviews, presence: true

  scope :active, -> { joins(:advisory_reviews_campaigns).merge(AdvisoryReviewsCampaign.pending).distinct }

  scope :by_status, lambda { |status|
    case status
    when "active"
      active
    when "complete"
      where.not(id: Campaign.active.select(:id))
    else
      all
    end
  }

  def progress_counts
    completed_reviews = advisory_reviews_campaigns.complete.map(&:advisory_review)
    # These counts don't represent actual published/closed states of the advisory review, but rather
    # representational colors in the progress bar of actionable advisories as a result of the campaign
    published_count = completed_reviews.count { |advisory_review| advisory_review.advisory && !advisory_review.advisory.withdrawn? }
    closed_count = completed_reviews.count { |advisory_review| advisory_review.advisory.nil? || advisory_review.advisory.withdrawn? }
    {
      published_count: published_count,
      closed_count: closed_count,
      total_count: advisory_reviews.count,
    }
  end

  def reviews_from_ids(cve_or_ghsa_ids)
    reviews = AdvisoryReview.where(ghsa_id: cve_or_ghsa_ids).or(
      AdvisoryReview.where(cve_id: cve_or_ghsa_ids),
    )

    unset_ids = cve_or_ghsa_ids - reviews.map(&:ghsa_id) - reviews.map(&:cve_id)
    raise ArgumentError, unset_ids.join(", ") if unset_ids.present?

    self.advisory_reviews = reviews
  end
end
