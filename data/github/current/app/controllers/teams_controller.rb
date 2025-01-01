# typed: true
# frozen_string_literal: true

class TeamsController < ApplicationController
  include OrganizationsHelper

  # We can safely skip the conditional access checks as all
  # actions in this controller simply redirect to the Orgs::TeamsController.
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  before_action :login_required
  before_action :current_organization_required
  before_action :current_team_required, only: :show

  before_action :team_members_only, only: :show
  before_action :org_members_only

  before_action :org_admins_only, only: :new

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:new]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:index]

  def index
    redirect_to teams_path(current_organization)
  end

  def show
    redirect_to team_path(current_team)
  end

  def new
    redirect_to new_team_path(current_organization)
  end

  private

  def current_organization_required
    render_404 unless current_organization
  end

  def current_team_required
    return render_404 if current_team.nil?
  end

  def current_team # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @current_team if defined? @current_team
    teams = current_organization.teams

    @current_team = \
      teams.find_by_id(params[:team_id]) ||
      teams.find_by_slug(params[:team_id])
  end

  def team_members_only
    render_404 if !current_team.visible_to?(current_user)
  end
end
