# typed: strict
# frozen_string_literal: true

class Sponsors::Activities::IndexComponent < ApplicationComponent
  DATE_FORMAT = "%b %-d, %Y"

  sig do
    params(sponsors_listing: SponsorsListing, period: Symbol, page: Integer, per_page: Integer).void
  end
  def initialize(sponsors_listing:, period:, page: 1, per_page: Sponsors::ActivitiesController::PER_PAGE)
    @sponsors_listing = sponsors_listing
    @page = page
    @per_page = per_page
    @period = T.let(fetch_or_fallback(SponsorsActivity::VALID_PERIODS, period, SponsorsActivity::DEFAULT_PERIOD),
      Symbol)
  end

  private

  sig { returns SponsorsListing }
  attr_reader :sponsors_listing

  sig { returns String }
  memoize def sponsorable_login
    sponsors_listing.sponsorable_login
  end

  sig { returns T::Boolean }
  def for_organization?
    sponsors_listing.for_organization?
  end

  sig { returns T::Boolean }
  def render?
    GitHub.sponsors_enabled?
  end

  sig { returns ActiveRecord::Relation }
  memoize def unordered_activities_scope
    # Just return an ActiveRecord::Relation without forcing this to load, since it's unpaginated and could load
    # thousands of records:
    sponsors_listing.activities.with_sponsorable_action.for_period(@period)
  end

  sig { returns T.nilable(SponsorsActivity) }
  memoize def earliest_activity_in_period
    T.unsafe(unordered_activities_scope).oldest_first.first
  end

  sig { returns T::Boolean }
  def no_activities?
    earliest_activity_in_period.nil?
  end

  sig { returns String }
  memoize def first_activity_date
    if @period == :alltime
      earliest_time = earliest_activity_in_period&.timestamp
      earliest_time&.strftime(DATE_FORMAT)
    else
      period_start
    end
  end

  sig { returns String }
  def period_menu_tooltip
    "Note: activity is not retroactive and is only available from December 2019"
  end

  sig { returns String }
  def period_start
    offset = ::SponsorsActivity::PERIOD_OFFSET_MAPPING[@period]
    start_date = if offset
      Date.current - offset.days
    else
      sponsors_listing.published_at || sponsors_listing.created_at
    end

    start_date.strftime(DATE_FORMAT)
  end

  sig { returns String }
  def period_end
    Date.today.strftime(DATE_FORMAT)
  end

  sig { returns T::Boolean }
  def show_sponsorship_log_link?
    Sponsorship.from_sponsor(sponsors_listing.sponsorable_id).any?
  end
end
