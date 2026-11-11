# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Members::PayoutProbationStatusComponent < ApplicationComponent
  def initialize(listing:)
    @listing = listing
  end

  private

  def probation_status_icon
    if @listing.completed_payout_probation?
      "check"
    else
      "dot-fill"
    end
  end

  def probation_status_color
    if @listing.payout_probation_started_at.nil? && @listing.payout_probation_ended_at.nil?
      :muted
    elsif @listing.on_payout_probation?
      :attention
    else
      :success
    end
  end

  def probation_status_text
    if @listing.payout_probation_started_at.nil? && @listing.payout_probation_ended_at.nil?
      "Not started"
    elsif @listing.on_payout_probation?
      "Pending"
    else
      "Complete"
    end
  end

  def probation_date_text
    return unless start = @listing.payout_probation_started_at
    start_date = start.strftime("%Y-%m-%d")

    if @listing.on_payout_probation?
      end_date = @listing.payout_probation_end_date.strftime("%Y-%m-%d")

      "Started #{start_date}, ends #{end_date}"
    elsif @listing.payout_probation_ended_at.present?
      end_date = @listing.payout_probation_ended_at.strftime("%Y-%m-%d")
      "Started #{start_date}, ended #{end_date}"
    end
  end
end
