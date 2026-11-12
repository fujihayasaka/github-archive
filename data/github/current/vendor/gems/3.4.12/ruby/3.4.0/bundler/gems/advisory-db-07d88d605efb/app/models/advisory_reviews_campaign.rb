# frozen_string_literal: true

class AdvisoryReviewsCampaign < ApplicationRecord
  CAMPAIGN_REVIEW_STATES = ["pending", "complete"].freeze

  belongs_to :advisory_review
  belongs_to :campaign

  scope :complete, -> { where.not(reviewed_at: nil) }
  scope :pending, -> { where(reviewed_at: nil) }

  def self.active_campaign_advisory_review_ids
    where(campaign_id: Campaign.active.select(:id)).pluck(:advisory_review_id)
  end
end
