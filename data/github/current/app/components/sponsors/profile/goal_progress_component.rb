# typed: true
# frozen_string_literal: true

class Sponsors::Profile::GoalProgressComponent < ApplicationComponent
  include AvatarHelper
  include ResilienceHelper

  SPONSORS_STACK_LIMIT = 7

  def initialize(
    sponsors_listing:,
    sponsor: nil,
    goal:,
    preview: false,
    header_class: "f5 text-bold mb-2",
    include_sponsor_names: true,
    **system_arguments
  )
    @sponsors_listing = sponsors_listing
    @sponsor = sponsor
    @goal = goal
    @preview = preview
    @header_class = header_class
    @include_sponsor_names = include_sponsor_names

    @system_arguments = system_arguments
    @system_arguments[:tag] = :div
    @system_arguments[:test_selector] = "sponsors-goals-progress-bar"
  end

  private

  attr_reader :sponsors_listing

  def render?
    return false unless sponsors_listing
    return true if @preview

    @goal.present?
  end

  def goal_percent_complete
    return 0 if @goal.blank?
    return 0 if sponsors_count.zero?

    [1, @goal.percent_complete.to_i].max
  end

  memoize def sponsors_to_render
    sponsorships = sponsorship_scope.privacy_public
      .preload({ sponsor: { sponsoring_parent_organization_profile: :organization } }, :sponsorable)
    sponsorships = with_database_error_fallback(fallback: sponsorships) do
      sponsorships.ranked(for_user: current_user)
    end
    sponsorships = sponsorships.order(created_at: :asc)

    if sponsor_already_sponsoring?
      [@sponsor] + sponsorships
        .where.not(sponsor_id: @sponsor.id)
        .limit(SPONSORS_STACK_LIMIT - 1)
        .map(&:linked_or_direct_sponsor)
    else
      sponsorships.limit(SPONSORS_STACK_LIMIT).map(&:linked_or_direct_sponsor)
    end
  end

  sig { returns Integer }
  memoize def how_many_others
    sponsors_count - 1
  end

  sig { returns String }
  def others_text
    "and #{how_many_others} #{"other".pluralize(how_many_others)}"
  end

  sig { returns T::Boolean }
  def show_sponsor_names?
    @include_sponsor_names && sponsors_to_render.any?
  end

  memoize def sponsorship_scope
    sponsors_listing.active_recurring_sponsorships
  end

  memoize def sponsors_count
    sponsorship_scope.count
  end

  memoize def sponsor_already_sponsoring?
    return false if @sponsor.nil?
    sponsors_listing.sponsor_exists_and_is_visible_to?(@sponsor.id,
      viewer: current_user)
  end

  def avatar_modifier_class
    if sponsors_count >= 3
      "AvatarStack--three-plus"
    elsif sponsors_count == 2
      "AvatarStack--two"
    end
  end

  def progress_data_attr
    return {} unless @preview

    monthly_sponsorship_dollars = sponsors_listing.subscription_value.to_i / 100

    {
      "data-preview-current-value-sponsors": sponsors_count,
      "data-preview-current-value-sponsorships": monthly_sponsorship_dollars
    }
  end

  def percentage_preview_css_class
    return unless @preview
    "js-sponsors-goal-percentage-preview"
  end

  def percentage_bar_preview_css_class
    return unless @preview
    "js-sponsors-goal-percentage-bar-preview"
  end

  def target_value_preview_css_class
    return unless @preview
    "js-sponsors-goal-target-progress-preview"
  end
end
