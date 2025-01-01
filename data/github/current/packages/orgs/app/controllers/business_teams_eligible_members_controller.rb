# typed: strict
# frozen_string_literal: true

class BusinessTeamsEligibleMembersController < Businesses::BusinessController
  include BusinessTeamHandlers
  include ApplicationController::VerifiedFetchDependency

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations

  allow_verified_fetch only: [:index]
  before_action :business_owner_required
  before_action :business_teams_enabled_required
  before_action :validate_team_parameter
  before_action only: [:index] do
    T.bind(self, Businesses::Concerns::BusinessAccess)
    business_access_required(allow_members: true)
  end

  MAX_PAGE_SIZE = 30

  sig { void }
  def index
    query = request.query_parameters[:query] || ""
    business_team = this_business.business_teams.find_by(slug: params[:team_slug])
    page_size = get_page_size

    eligible_members = business_team.eligible_members_in_enterprise(current_user, query: query)
    eligible_member_payloads = eligible_members.limit(page_size).map do |user|
      business_team_member_payload(user)
    end

    render(json: { users: eligible_member_payloads, totalEligibleUsersInEnterprise: eligible_members.count })
  end

  private

  sig { returns(Integer) }
  def get_page_size
    page_size = params.fetch(:page_size, MAX_PAGE_SIZE).to_i
    page_size = MAX_PAGE_SIZE unless page_size > 0 && page_size <= MAX_PAGE_SIZE
    page_size
  end

  sig { void }
  def business_teams_enabled_required
    render_404 unless BusinessTeam.enabled_for_enterprise?(business: current_business)
  end

  sig { void }
  def validate_team_parameter
    business_team = this_business.business_teams.find_by(slug: params[:team_slug])
    unless business_team.present?
      render(json: { data: { error: "Team not found." } }, status: :not_found)
    end
  end
end
