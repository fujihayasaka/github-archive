# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::FraudReviews::ReviewComponent < ApplicationComponent
  DATE_FORMAT = "%b %-d, %Y"

  def initialize(review:)
    @review = review
  end

  private

  def render?
    @review.present?
  end

  memoize def sponsors_listing
    @review.sponsors_listing
  end

  def sponsorable
    sponsors_listing.sponsorable
  end

  def sponsorable_login
    sponsors_listing.sponsorable_login
  end

  def reviewer
    @review.reviewer
  end

  def created_at_date
    @review.created_at.strftime(DATE_FORMAT)
  end

  def reviewed_at_date
    @review.reviewed_at&.strftime(DATE_FORMAT)
  end

  def matchable
    sponsors_listing.matchable?
  end

  def next_payout_date
    sponsors_listing.next_payout_date&.strftime(DATE_FORMAT)
  end

  def payout_probation_end_date_string
    return unless probation_end_date = sponsors_listing.payout_probation_end_date

    prefix = if probation_end_date <= Date.today
      "Payout probation ended on"
    else
      "Payout probation ends on"
    end

    "#{prefix} #{probation_end_date.strftime(DATE_FORMAT)}"
  end

  def state_icon
    if @review.resolved?
      "check"
    elsif @review.flagged?
      "alert"
    else
      "dot-fill"
    end
  end

  def state_icon_color
    if @review.resolved?
      :success
    elsif @review.flagged?
      :attention
    else
      :default
    end
  end
end
