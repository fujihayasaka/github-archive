# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Members::Activities::ActivityComponent < ApplicationComponent
  include PlanHelper

  DATETIME_FORMAT = "%b %-d %Y, %l:%M %p"

  def initialize(activity:)
    @activity = activity
  end

  private

  def render?
    @activity.present?
  end

  memoize def sponsor
    @activity.sponsor
  end

  def action
    action = case @activity.action
    when "new_sponsorship" then "New sponsorship"
    when "cancelled_sponsorship" then "Cancelled sponsorship"
    when "tier_change" then "Tier changed"
    when "pending_change" then "Pending change"
    when "refund" then "Refund"
    else
      "N/A"
    end
    suffix = @activity.payment_source == "patreon" ? "(Patreon)" : ""
    [action, suffix].join(" ")
  end

  memoize def timestamp
    @activity.timestamp&.strftime(DATETIME_FORMAT)
  end

  memoize def current_tier
    @activity.sponsors_tier
  end

  memoize def old_tier
    @activity.old_sponsors_tier
  end
end
