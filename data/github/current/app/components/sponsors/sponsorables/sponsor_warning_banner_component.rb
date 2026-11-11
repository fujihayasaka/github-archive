# typed: true
# frozen_string_literal: true

class Sponsors::Sponsorables::SponsorWarningBannerComponent < ApplicationComponent
  def initialize(sponsorable:, sponsor:)
    @sponsorable = sponsorable
    @sponsor = sponsor
  end

  def call
    render(
      Primer::Beta::Flash.new(scheme: :warning, full: true, test_selector: "sponsor-warning-banner")
        .with_content(warning_message)
    )
  end

  private

  attr_reader :sponsor, :sponsorable

  def render?
    logged_out? || one_time_payment_still_processing?
  end

  def warning_message
    if logged_out?
      "You must be logged in to sponsor #{sponsorable}"
    elsif one_time_payment_still_processing?
      "We are still processing your last one-time payment to #{sponsorable}. You cannot make another " \
        "one-time payment until your last one has finished processing."
    end
  end

  def logged_out?
    !logged_in?
  end

  def one_time_payment_still_processing?
    sponsor.processing_one_time_payment_to?(sponsorable)
  end
end
