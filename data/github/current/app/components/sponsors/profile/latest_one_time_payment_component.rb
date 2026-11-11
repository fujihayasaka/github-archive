# typed: true
# frozen_string_literal: true

class Sponsors::Profile::LatestOneTimePaymentComponent < ApplicationComponent
  attr_reader :sponsorship, :sponsorable_metadata

  # sponsorship - Sponsorship object
  # sponsorable_metadata - optional Hash of metadata set by the sponsorable
  def initialize(sponsorship:, sponsorable_metadata: nil)
    @sponsorship = sponsorship
    @sponsorable_metadata = sponsorable_metadata
  end

  def render?
    latest_one_time_payment_activity && sponsorship
  end

  private

  memoize def latest_one_time_payment_activity
    sponsorship&.latest_one_time_payment_activity
  end

  def latest_one_time_payment_amount
    latest_one_time_payment_activity.monthly_price_in_dollars.to_i
  end

  delegate :sponsorable, :sponsor, to: :sponsorship

  def sponsors_log_path
    if sponsor.organization?
      settings_org_sponsors_log_path(sponsor)
    else
      settings_user_sponsors_log_path
    end
  end

  def one_time_payment_date
    latest_one_time_payment_activity.timestamp.strftime("%B %-d, %Y")
  end

  memoize def amount_readable_by_viewer?
    sponsorship.amount_readable_by?(current_user)
  end
end
