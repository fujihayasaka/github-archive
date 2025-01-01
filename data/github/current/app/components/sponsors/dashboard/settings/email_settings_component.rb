# typed: strict
# frozen_string_literal: true

class Sponsors::Dashboard::Settings::EmailSettingsComponent < ApplicationComponent
  extend T::Sig

  sig { params(sponsorable: GitHubSponsors::Types::Sponsorable).void }
  def initialize(sponsorable:)
    @sponsorable = sponsorable
  end

  private

  sig { returns(GitHubSponsors::Types::Sponsorable) }
  attr_reader :sponsorable

  delegate :sponsors_listing, to: :sponsorable

  sig { returns(T::Boolean) }
  def render?
    GitHub.sponsors_enabled?
  end

  sig { returns(SponsorsEmailOptOuts) }
  memoize def opt_outs
    sponsors_listing.email_opt_outs
  end

  sig { returns(T::Boolean) }
  def opted_out_of_all?
    opt_outs.opted_out_of_all?
  end

  class CheckboxConfig < T::Struct
    const :name, Symbol
    const :label, String
    const :opted_out, T::Boolean
  end

  sig { returns(T::Array[CheckboxConfig]) }
  def checkbox_params
    params = [
      CheckboxConfig.new(
        name: :new_sponsorships,
        label: "New sponsorships",
        opted_out: opt_outs.opted_out_of_new_sponsorships?
      ),
      CheckboxConfig.new(
        name: :upgrade_notices,
        label: "Sponsorship upgraded",
        opted_out: opt_outs.opted_out_of_upgrade_notices?
      ),
      CheckboxConfig.new(
        name: :goal_completed,
        label: "Goal completed",
        opted_out: opt_outs.opted_out_of_goal_completed?
      ),
      CheckboxConfig.new(
        name: :milestone_reached,
        label: "Milestone reached",
        opted_out: opt_outs.opted_out_of_milestone_reached?
      ),
      CheckboxConfig.new(
        name: :cancelled_sponsorships,
        label: "Sponsorship cancelled",
        opted_out: opt_outs.opted_out_of_cancelled_sponsorships?
      ),
    ]

    if sponsors_listing.matchable?
      params << CheckboxConfig.new(
        name: :reached_match_cap,
        label: "Reached GitHub Sponsors Matching Fund cap",
        opted_out: opt_outs.opted_out_of_reached_match_cap?
      )
    end

    params
  end
end
