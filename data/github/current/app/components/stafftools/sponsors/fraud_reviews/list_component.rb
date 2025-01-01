# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::FraudReviews::ListComponent < ApplicationComponent
  DATE_FORMAT    = "%b %-d, %Y"
  RESOLVED_ICON  = "check"
  RESOLVED_COLOR = :success
  FLAGGED_ICON   = "alert"
  FLAGGED_COLOR  = :danger
  PENDING_ICON   = "dot-fill"
  PENDING_COLOR  = :attention
  HIDDEN_CLASS   = "Details-content--hidden"
  HIDDEN_CONTENT = 2
  DISPLAY_EXPAND = 3

  # sponsors_fraud_reviews - an Array of SponsorsFraudReview records
  # sponsorable - the sponsorable User or Organization the fraud reviews are about
  def initialize(sponsors_fraud_reviews:, sponsorable:)
    @sponsors_fraud_reviews = sponsors_fraud_reviews
    @sponsorable = sponsorable
    @flagged = 0
  end

  private

  def render?
    @sponsors_fraud_reviews.present? && @sponsorable.present?
  end

  memoize def total_fraud_reviews
    @sponsors_fraud_reviews.size
  end

  def increase_expand_flagged_count
    @flagged += 1
  end

  def expand_flagged_count
    @flagged
  end

  def content_details_classes(index, review)
    if should_hidden_content?(index)
      increase_expand_flagged_count if review.flagged?
      HIDDEN_CLASS
    end
  end

  def should_hidden_content?(index)
    index > HIDDEN_CONTENT
  end

  def expand_content_to_shown
    total_fraud_reviews - DISPLAY_EXPAND
  end

  def should_expand_content?
    expand_content_to_shown.positive?
  end

  def review_state_icon(review)
    icon, color = if review.resolved?
      [RESOLVED_ICON, RESOLVED_COLOR]
    elsif review.flagged?
      [FLAGGED_ICON, FLAGGED_COLOR]
    else
      [PENDING_ICON, PENDING_COLOR]
    end

    render Primer::Beta::Octicon.new(icon: icon, color: color, mr: 2)
  end

  def created_at_date(review)
    review.created_at.strftime(DATE_FORMAT)
  end

  def reviewed_at_date(review)
    review.reviewed_at&.strftime(DATE_FORMAT)
  end
end
