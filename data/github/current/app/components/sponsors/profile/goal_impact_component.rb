# typed: true
# frozen_string_literal: true

class Sponsors::Profile::GoalImpactComponent < ApplicationComponent
  include AvatarHelper

  EMPTY_COLLECTION = WillPaginate::Collection.new(1, 0, 0)

  def initialize(
    sponsorable:,
    goal:,
    sponsorships: EMPTY_COLLECTION,
    selected_tier: nil,
    currently_sponsoring: false
  )
    @sponsorable = sponsorable
    @goal = goal
    @sponsorships = sponsorships
    @selected_tier = selected_tier
    @currently_sponsoring = currently_sponsoring
  end

  private

  def render?
    return false if @selected_tier.blank?
    return false unless @goal&.active?
    return false unless logged_in?

    !@currently_sponsoring
  end

  def sponsorships_count
    @sponsorships.total_entries
  end

  memoize def percentage_impact
    begin
      new_value = if @goal.monthly_sponsorship_amount?
        money = Billing::Money.new(@goal.current_value + @selected_tier.monthly_price_in_cents)
        money.dollars
      else
        @goal.current_value + 1
      end

      # ensure it's at least 1
      new_percentage = [(new_value * 100 / @goal.target_value).round, 1].max
      # add 1 if the new percentage rounds down to the current percentage
      new_percentage += 1 if new_percentage == @goal.percent_complete

      # don't go over 100
      [100, new_percentage].min
    end
  end

  def will_complete?
    percentage_impact == 100
  end

  def progress_bar_css_class
    if will_complete?
      "sponsors-goal-completed-bar"
    else
      "sponsors-goal-progress-bar"
    end
  end
end
