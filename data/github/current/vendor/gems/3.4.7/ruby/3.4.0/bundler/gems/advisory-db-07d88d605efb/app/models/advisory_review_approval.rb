# frozen_string_literal: true

class AdvisoryReviewApproval < ApplicationRecord
  belongs_to :user
  belongs_to :advisory_review

  scope :approved, -> { where.not(approved_at: nil) }
  scope :unapproved, -> { where(approved_at: nil) }
  scope :current_review_request, -> { joins(:advisory_review).where("advisory_review_approvals.created_at > advisory_reviews.review_requested_at") }

  REQUIRED_APPROVAL_COUNT = 2
end
