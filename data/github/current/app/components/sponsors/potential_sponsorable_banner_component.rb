# typed: true
# frozen_string_literal: true

class Sponsors::PotentialSponsorableBannerComponent < ApplicationComponent
  extend T::Sig

  # preview_mode - Boolean indicating whether we want to preview the banner in stafftools versus show it for real
  #                with a dismissal form for the potential sponsorable
  sig { params(potential_sponsorship: T.nilable(PotentialSponsorship), preview_mode: T.nilable(T::Boolean)).void }
  def initialize(potential_sponsorship: nil, preview_mode: false)
    @potential_sponsorship = potential_sponsorship
    @preview_mode = !!preview_mode
  end

  private

  delegate :sponsors_listing, to: :potential_sponsorable

  sig { returns T.nilable(T::Boolean) }
  def render?
    return false unless GitHub.sponsors_enabled? && logged_in?
    return false unless potential_sponsorship
    return false unless potential_sponsorable
    return false if T.must(potential_sponsorable).spammy?
    return false if sponsors_listing && !sponsors_listing.draft?
    if preview_mode? && current_user.can_admin_sponsors_listings?
      true
    else
      !current_user.dismissed_notice?(PotentialSponsorship::NOTICE) &&
        # Make sure if we were given a PotentialSponsorship, it's one for a potential sponsorable the viewer
        # has admin rights over:
        potential_sponsorable_ids.include?(T.must(potential_sponsorable).id)
    end
  end

  sig { returns T::Boolean }
  def preview_mode?
    @preview_mode
  end

  sig { returns T.nilable(PotentialSponsorship) }
  memoize def potential_sponsorship
    # If we were explicitly given a potential sponsorship, use that one:
    return @potential_sponsorship if @potential_sponsorship

    # Otherwise, look up the most recent potential sponsorship, omitting ones they've already dismissed so that we
    # respect the user's input and don't repeatedly show the same banner:
    PotentialSponsorship.for_potential_sponsorable(potential_sponsorable_ids).with_pending_state.most_recent.first
  end

  sig { returns T.nilable(User) }
  memoize def potential_sponsorable
    potential_sponsorship&.potential_sponsorable
  end

  sig { returns T::Array[Integer] }
  memoize def potential_sponsorable_ids
    # All the users and orgs the viewer would have permission to create a SponsorsListing for:
    current_user.potential_sponsorable_ids
  end

  sig { returns Integer }
  def total_potential_sponsors
    # Include even those that have been dismissed when counting how many people might potentially sponsor the
    # user/org:
    PotentialSponsorship.for_potential_sponsorable(potential_sponsorable).without_sponsorship_created_state
      .distinct.count(:potential_sponsor_id)
  end

  sig { returns String }
  def who_is_sponsoring
    total_potential_sponsors <= 1 ? "Someone" : "People"
  end

  sig { returns T.nilable(String) }
  def who_would_be_sponsored
    potential_sponsorable&.user? ? "you" : potential_sponsorable&.safe_profile_name
  end

  sig { returns String }
  def call_to_action_url
    if sponsors_listing
      sponsorable_dashboard_path(potential_sponsorable)
    else
      sponsorable_signup_path(potential_sponsorable)
    end
  end

  sig { returns String }
  def call_to_action_text
    if sponsors_listing
      "Complete your GitHub Sponsors profile"
    else
      "Create a GitHub Sponsors profile"
    end
  end

  sig { returns String }
  def standard_message
    if sponsors_listing
      "Someone appreciates your work and would like to fund you, but you haven't completed your GitHub Sponsors " \
        "profile."
    else
      "We think you might benefit from having a GitHub Sponsors profile, because someone appreciates your work and " \
        "would like to fund you."
    end
  end
end
