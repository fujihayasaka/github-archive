# typed: strict
# frozen_string_literal: true

class Businesses::CopilotLicensingBusinessTeamAssignmentController < Businesses::BusinessController

  before_action :dotcom_required
  before_action :business_owner_required
  before_action :business_teams_enabled_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :ensure_enterprise_copilot_licensing_enabled

  javascript_bundle :copilot

  include ApplicationController::VerifiedFetchDependency

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Billing,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    only: [:index]

  allow_verified_fetch only: [:create, :destroy]

  sig { void }
  def index
    business_teams = this_business.business_teams
    if params[:query].present?
      query = ActiveRecord::Base.sanitize_sql_like(params[:query])
      business_teams = business_teams.where("name like ?", "%#{query}%")
    end

    copilot_plan = copilot_business.copilot_plan # All business teams are assigned to the owner, and have the owner's plan.

    teams_with_copilot_access = []
    teams_without_copilot_access = []

    # Get seat count for all business teams
    team_ids = business_teams.pluck(:id)

    seat_assignment_team_ids = Copilot::SeatAssignment
      .for_business_team_id(team_ids)
      .pluck(:assignable_id)

    business_teams.each do |business_team|
      team_information = {
        name: business_team.name,
        id: business_team.id,
        memberCount: business_team.member_ids.count,
        copilotPlan: copilot_plan,
        licenseCount: 0,
        expirationDate: T.let(nil, T.nilable(Date)),
      }

      # A team can have Copilot access, and not have any seats assigned. Business Teams only assign seats if there's no other seat available for the users.
      team_has_seats = seat_assignment_team_ids.include?(business_team.id)

      unless team_has_seats
        teams_without_copilot_access << team_information
        next
      end

      team_seats = Copilot::Seat
        .joins(:seat_assignment)
        .where(copilot_seat_assignments: { assignable_type: "BusinessTeam", assignable_id: business_team.id })

      team_information[:licenseCount] = team_seats.count
      cancellation_dates = team_seats.pluck(:pending_cancellation_date).compact.uniq

      if cancellation_dates.any?
        team_information[:expirationDate] = cancellation_dates.min # Use the earliest expiration date if seats have different expiration dates
      end

      teams_with_copilot_access << team_information
    end

    render json: {
      withCopilotAccess: teams_with_copilot_access,
      withoutCopilotAccess: teams_without_copilot_access,
    }
  end

  sig { void }
  def create
    if params[:team_ids].blank?
      render json: { error: "Missing or empty team_ids" }, status: :bad_request
      return
    end

    ids = params[:team_ids].map(&:to_i)
    business_teams = BusinessTeam.where(business: this_business, id: ids).to_a
    result = copilot_business.assign(business_teams, current_user)

    if result.ok?
      head :ok
    else
      render json: { error: result.error }, status: :unprocessable_entity
    end
  end

  sig { void }
  def destroy
    if params[:team_ids].blank?
      render json: { error: "Missing or empty team_ids" }, status: :bad_request
      return
    end

    ids = params[:team_ids].map(&:to_i)
    business_teams = BusinessTeam.where(business: this_business, id: ids).to_a

    business_teams.each do |team|
      Copilot::SeatManagement::BusinessTeamDeletedJob.perform_later(
        team_id: team.id,
        business_id: this_business.id,
        actor_id: current_user.id
      )
    end

    # There isn't a way to return the status of the job, so we assume success.
    head :ok
  end

  private

  sig { returns(Copilot::Business) }
  memoize def copilot_business
    ::Copilot::Business.new(this_business)
  end

  sig { void }
  def business_teams_enabled_required
    render_404 unless BusinessTeam.enabled_for_enterprise?(business: current_business)
  end
end
