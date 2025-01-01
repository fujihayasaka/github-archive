# typed: strict
# frozen_string_literal: true

class Sponsors::Goals::RetirementsController < ApplicationController
  include Sponsors::AdminableControllerValidations

  before_action :non_waitlisted_sponsors_listing_required

  sig { void }
  def create
    listing = T.must_because(sponsorable_sponsors_listing) do
      "#non_waitlisted_sponsors_listing_required ensures non-nil"
    end
    active_goal = listing.active_goal
    if active_goal.present?
      active_goal.retire!
      instrument_event(action: :RETIRED, goal: active_goal)

      flash[:notice] = "Your active goal has been retired."
    end

    redirect_to sponsorable_dashboard_goals_path(sponsorable)
  end

  private

  sig { params(action: T.any(String, Symbol), goal: SponsorsGoal).void }
  def instrument_event(action:, goal:)
    GlobalInstrumenter.instrument("sponsors.goal_event", {
      actor: current_user,
      listing: sponsorable_sponsors_listing,
      goal: goal,
      action: action,
      sponsorable: sponsorable,
    })
  end

  sig { returns T.any(Symbol, GitHubSponsors::Types::Sponsorable) }
  def target_for_conditional_access
    sponsorable || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
