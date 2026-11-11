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

  TEAMS_PER_PAGE = 20

  sig { void }
  def index
    query_with_access = params[:withAccess] == "true"
    page = params[:page] || 1
    total_count = 0

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
      .where(access_revoked_at: nil)
      .pluck(:assignable_id)

    if query_with_access
      filtered_team_ids = seat_assignment_team_ids
    else
      filtered_team_ids = team_ids - seat_assignment_team_ids
    end

    total_count = filtered_team_ids.count

    filtered_team_ids.paginate(page: page, per_page: TEAMS_PER_PAGE).each do |business_team_id|
      business_team = T.must(BusinessTeam.find_by(id: business_team_id))

      team_information = {
        name: business_team.name,
        id: business_team.id,
        memberCount: business_team.member_ids.count,
        copilotPlan: copilot_plan,
        expirationDate: T.let(nil, T.nilable(Date)),
        teamUrl: enterprise_team_path(this_business.slug, business_team.slug, only_path: true),
      }

      unless query_with_access
        teams_without_copilot_access << team_information
        next
      end

      # If we're here, we know that this BusinessTeam has an assignment
      # so we're only going to fill the teams_with_copilot_access array
      cancellation_date = Copilot::SeatAssignment
        .where(assignable_type: "BusinessTeam")
        .where(assignable_id: business_team_id)
        .first&.pending_cancellation_date

      team_information[:expirationDate] = cancellation_date

      teams_with_copilot_access << team_information
    end

    render json: {
      withCopilotAccess: teams_with_copilot_access,
      withoutCopilotAccess: teams_without_copilot_access,
      totalCount: total_count,
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
    result = copilot_business.unassign(business_teams, current_user)

    if result.ok?
      head :ok
    else
      render json: { error: result.error }, status: :unprocessable_entity
    end
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
