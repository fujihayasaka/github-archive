# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Members::Activities::FilterComponent < ApplicationComponent
  def initialize(sponsorable_login:, tiers:, filter: {})
    @sponsorable_login = sponsorable_login
    @tiers = tiers
    @filter = filter
  end

  private

  attr_reader :sponsorable_login, :tiers, :filter

  def render?
    @sponsorable_login.present? && @tiers.present? && GitHub.sponsors_enabled?
  end

  def sponsor_action_all_params
    all_params.except(:sponsor_action)
  end

  def current_tier_all_params
    all_params.except(:current_tier)
  end

  def old_tier_all_params
    all_params.except(:old_tier)
  end

  def search_by_handle_path
    stafftools_sponsors_member_activities_path(sponsorable_login, all_params.except(:handle))
  end

  def search_by_date
    stafftools_sponsors_member_activities_path(sponsorable_login, all_params.except(:date))
  end

  def selected_tier(id)
    tiers_options[id&.to_i] || "All"
  end

  memoize def tiers_options
    tiers.pluck(:id, :name).to_h
  end

  def selected_sponsor_action(sponsor_action)
    sponsors_actions[sponsor_action&.to_sym] || "All"
  end

  memoize def sponsors_actions
    {
      new_sponsorship: "New sponsorship",
      cancelled_sponsorship: "Cancelled sponsorship",
      tier_change: "Tier changed",
      refund: "Refund",
      pending_change: "Pending change",
    }
  end

  memoize def all_params
    {
      handle: filter[:handle],
      sponsor_action: filter[:sponsor_action],
      current_tier: filter[:current_tier],
      old_tier: filter[:old_tier],
      timestamp: filter[:timestamp],
      start_at: filter[:start_at],
      end_at: filter[:end_at]
    }.compact
  end
end
