# typed: true
# frozen_string_literal: true

class Sponsors::GoalsController < ApplicationController
  extend T::Sig
  include Sponsors::AdminableControllerValidations

  before_action :non_waitlisted_sponsors_listing_required
  before_action :active_goal_required, only: [:edit, :update]
  before_action :add_csp_exceptions

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:index, :new, :edit]

  depends_on_clusters ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:index, :new, :edit],
    optional: true

  CSP_EXCEPTIONS = {
    form_action: [
      Billing::StripeConnect::Account::STRIPE_CONNECT_URL,
    ] + Sponsors::ShareButtonComponent::SHARE_URL_BY_SOCIAL.values,
    frame_src: [
      "#{GitHub.scheme}://#{GitHub.host_name}",
    ]
  }.freeze

  # paginate completed goals
  COMPLETED_GOALS_PER_PAGE = 50

  stylesheet_bundle :sponsors

  def index
    completed_goals = sponsors_listing.goals.completed
      .preload(contributions: :sponsor)
      .paginate(page: current_page, per_page: COMPLETED_GOALS_PER_PAGE)
      .order(completed_at: :desc)

    render "sponsors/dashboard/goals/index", locals: {
      sponsorable: sponsorable,
      sponsors_listing: sponsors_listing,
      active_goal: active_goal,
      completed_goals: completed_goals,
    }
  end

  def new
    render "sponsors/dashboard/goals/new", locals: {
      sponsorable: sponsorable,
      sponsors_listing: sponsors_listing,
      goal: SponsorsGoal.new,
    }
  end

  def create
    goal = sponsors_listing.goals.new(goal_params)

    if goal.save
      instrument_event(action: :CREATED, goal: goal)

      flash[:notice] = "You successfully created a goal! 🎉"
      redirect_to sponsorable_dashboard_goals_path(sponsorable)
    else
      flash[:error] = goal.errors.full_messages.join(", ")

      render "sponsors/dashboard/goals/new", locals: {
        sponsorable: sponsorable,
        sponsors_listing: sponsors_listing,
        goal: goal,
      }
    end
  end

  def edit
    render "sponsors/dashboard/goals/edit", locals: {
      sponsorable: sponsorable,
      sponsors_listing: sponsors_listing,
      goal: active_goal,
    }
  end

  def update
    active_goal = T.must_because(self.active_goal) { "#active_goal_required ensures non-nil" }

    if active_goal.update(goal_params)
      instrument_event(action: :UPDATED, goal: active_goal)

      flash[:notice] = "Your active goal has been updated!"
      redirect_to sponsorable_dashboard_goals_path(sponsorable)
    else
      flash[:error] = active_goal.errors.full_messages.join(", ")

      render "sponsors/dashboard/goals/edit", locals: {
        sponsorable: sponsorable,
        sponsors_listing: sponsors_listing,
        goal: active_goal,
      }
    end
  end

  private

  sig { returns(SponsorsListing) }
  def sponsors_listing
    T.must_because(sponsorable_sponsors_listing) { "#non_waitlisted_sponsors_listing_required ensures non-nil" }
  end

  sig { returns ActionController::Parameters }
  def goal_params
    params.require(:goal).permit(:kind, :target_value, :description)
  end

  sig { returns T.nilable(SponsorsGoal) }
  def active_goal
    sponsors_listing.active_goal
  end

  sig { void }
  def active_goal_required
    return if active_goal.present?
    redirect_to new_sponsorable_dashboard_goal_path
  end

  sig { params(action: Symbol, goal: SponsorsGoal).void }
  def instrument_event(action:, goal:)
    GlobalInstrumenter.instrument("sponsors.goal_event", {
      actor: current_user,
      listing: sponsors_listing,
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
