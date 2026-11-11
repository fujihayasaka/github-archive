# typed: true
# frozen_string_literal: true

class Hovercards::TeamsController < ApplicationController
  before_action :require_xhr, only: :show

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    only: [:show]

  MEGA_TEAM_THRESHOLD = 50_000
  MEMBERS_TO_DISPLAY = 3

  def show
    return render_404 unless team.readable_by?(current_user)
    render "hovercards/teams/show",
      locals: {
      team: team,
      members: members,
      remaining_members_count: remaining_members_count,
    },
    layout: false
  end

  private

  memoize def this_organization
    Organization.find_by!(login: params[:org])
  end

  memoize def team
    this_organization.teams.find_by!(slug: params[:team_slug])
  end

  def target_for_conditional_access
    this_organization
  end

  def scope_builder
    Team::Membership::ScopeBuilder.new(
      team_id: team.id,
      viewer: current_user,
      max_members_limit: MEGA_TEAM_THRESHOLD,
    )
  end

  def members
    team.ranked_members_for(
      current_user,
      scope: scope_builder.scope,
      direction: "desc",
    ).first(MEMBERS_TO_DISPLAY)
  end

  memoize def members_count
    scope_builder.count
  end

  def remaining_members_count
    [members_count - MEMBERS_TO_DISPLAY, 0].max
  end
end
