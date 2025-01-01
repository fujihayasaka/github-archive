# typed: strict
# frozen_string_literal: true

class Sponsors::Activities::ActivityComponent < ApplicationComponent
  extend T::Sig
  include AvatarHelper
  include BotHelper
  include PlanHelper

  VIEWER_ROLES = T.let(%i(sponsor sponsorable).freeze, T::Array[Symbol])

  # activity - the sponsorship log activity to display
  # first - whether this is the first activity in a list
  # last - whether this is the last activity in a list
  # viewer_role - whose side the viewer represents, the sponsor's or the sponsorable's, either because they are
  #               the user themselves or because they belong to an org that is the sponsor or sponsorable; choose
  #               between :sponsor or :sponsorable
  sig do
    params(
      activity: T.nilable(SponsorsActivity),
      first: T.nilable(T::Boolean),
      last: T.nilable(T::Boolean),
      viewer_role: Symbol
    ).void
  end
  def initialize(activity:, first:, last:, viewer_role:)
    @activity = activity
    @first = T.let(fetch_or_fallback([true, false], first, false), T::Boolean)
    @last = T.let(fetch_or_fallback([true, false], last, false), T::Boolean)
    @viewer_role = T.let(fetch_or_fallback(VIEWER_ROLES, viewer_role, nil), T.nilable(Symbol))
  end

  private

  sig { returns SponsorsActivity }
  def activity
    T.must_because(@activity) { "#render? ensures non-nil" }
  end

  sig { returns Symbol }
  def viewer_role
    T.must_because(@viewer_role) { "#render? ensures non-nil" }
  end

  delegate :sponsors_tier, :old_sponsors_tier, :repository, :old_repository, :sponsors_listing, to: :activity
  delegate :sponsorable_login, to: :sponsors_listing

  sig { returns T::Boolean }
  def render?
    @activity.present? && @viewer_role.present?
  end

  sig { returns T::Boolean }
  def first?
    @first
  end

  sig { returns T::Boolean }
  def last?
    @last
  end

  sig { returns T::Boolean }
  memoize def via_bulk_sponsorship?
    activity.via_bulk_sponsorship?
  end

  sig { returns String }
  def timeline_item_classes
    class_names("TimelineItem", "pt-0" => first?, "pb-0" => last?)
  end

  sig { returns T::Boolean }
  def viewer_represents_sponsor?
    viewer_role == :sponsor
  end

  sig { returns String }
  memoize def sponsorable_path_for_sponsor
    # Use the direct sponsor on the activity because that's the user/organization that paid. Want to give a link
    # so that the viewer is taken to the page with the right account chosen to pay:
    sponsorable_path(sponsorable_login, sponsor: activity.sponsor)
  end

  sig { returns GitHubSponsors::Types::Sponsor }
  memoize def sponsor
    activity.linked_or_direct_sponsor
  end

  sig { returns T::Boolean }
  memoize def organization_sponsorable?
    sponsors_listing.for_organization?
  end

  sig { returns T::Boolean }
  def organization_sponsor?
    sponsor.organization?
  end

  sig { returns T::Boolean }
  def show_sponsor_name_and_avatar?
    organization_sponsor? || !viewer_represents_sponsor?
  end

  sig { returns String }
  memoize def sponsor_plan_duration
    sponsor.sponsors_plan_duration
  end

  sig { returns String }
  def old_frequency_label
    if activity.one_time_old_tier?
      "one-time"
    else
      "/ #{sponsor_plan_duration}"
    end
  end

  sig { returns String }
  memoize def frequency_label
    if activity.one_time_tier?
      render Primer::Beta::Link.new(
        href: "#{GitHub.help_url}/sponsors/sponsoring-open-source-contributors/sponsoring-an-open-source-contributor-through-github",
        classes: "Link--inTextBlock",
        test_selector: "one-time-frequency-link",
      ).with_content("one-time")
    else
      "/ #{sponsor_plan_duration}"
    end
  end

  sig { returns T.nilable(Repository) }
  memoize def repo_gained
    activity.repository_sponsor_gained_access_to
  end

  sig { returns T.nilable(Repository) }
  memoize def repo_lost
    activity.repository_sponsor_lost_access_to
  end

  sig { returns String }
  def whose_billing_cycle
    if organization_sponsor? || !viewer_represents_sponsor?
      "@#{sponsor}'s"
    else
      "your"
    end
  end

  sig { returns String }
  def badge_color
    class_names("color-fg-sponsors" => activity.is_increase?)
  end

  sig { returns T.nilable(String) }
  def badge_octicon
    if activity.is_new_sponsorship? || activity.is_sponsor_match_disabled?
      "heart-fill"
    elsif activity.is_cancelled_sponsorship?
      "x"
    elsif activity.is_pending_cancellation? || activity.is_pending_tier_change?
      "history"
    elsif activity.is_tier_change?
      if activity.is_increase?
        "arrow-up"
      else
        "arrow-down"
      end
    elsif activity.is_refund?
      "dash"
    end
  end

  sig { returns String }
  def sponsor_pronoun
    if organization_sponsor? || !viewer_represents_sponsor?
      "their"
    else
      "your"
    end
  end

  sig { returns T::Boolean }
  def include_preposition_for_sponsorable_after_description?
    activity.is_cancelled_sponsorship?
  end

  sig { returns T::Boolean }
  def show_sponsorable_after_description?
    activity.is_new_sponsorship? || activity.is_cancelled_sponsorship?
  end

  sig { returns T::Boolean }
  def show_sponsorable_at_end?
    return false unless viewer_represents_sponsor?
    activity.is_tier_change? || activity.is_pending_tier_change? || activity.is_refund? ||
      activity.is_pending_cancellation?
  end

  sig { returns T.nilable(String) }
  def description
    if activity.is_new_sponsorship?
      if activity.one_time_tier?
        "sponsored"
      else
        "started sponsoring"
      end
    elsif activity.is_cancelled_sponsorship?
      "cancelled #{sponsor_pronoun} sponsorship"
    elsif activity.is_tier_change?
      "updated #{sponsor_pronoun} sponsorship"
    elsif activity.is_pending_cancellation?
      "scheduled a sponsorship cancellation"
    elsif activity.is_pending_tier_change?
      "scheduled a sponsorship update"
    elsif activity.is_refund?
      "received a refund for #{sponsor_pronoun} subscription"
    end
  end

  sig { returns String }
  def repo_loss_description
    if activity.is_pending_change?
      "will remove access to"
    else
      "removed access to"
    end
  end

  sig { returns String }
  memoize def price
    amount_in_dollars = if sponsor_on_yearly_plan?
      sponsors_tier.yearly_price_in_dollars
    else
      sponsors_tier.monthly_price_in_dollars
    end

    casual_currency(amount_in_dollars)
  end

  sig { returns T::Boolean }
  memoize def sponsor_on_yearly_plan?
    sponsor.yearly_sponsors_plan?
  end

  sig { returns String }
  def old_price
    amount_in_dollars = if sponsor_on_yearly_plan?
      old_sponsors_tier.yearly_price_in_dollars
    else
      old_sponsors_tier.monthly_price_in_dollars
    end

    casual_currency(amount_in_dollars)
  end

  sig { returns T::Boolean }
  def is_possessive?
    activity.is_sponsor_match_disabled?
  end

  sig { returns T::Boolean }
  def show_matching_icon?
    activity.is_new_sponsorship? && activity.matched_sponsorship?
  end

  sig { returns T::Boolean }
  def show_patreon_icon?
    activity.patreon? && activity.is_new_sponsorship?
  end
end
