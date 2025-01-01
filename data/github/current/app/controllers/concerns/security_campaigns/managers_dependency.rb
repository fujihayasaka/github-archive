# typed: true
# frozen_string_literal: true

module SecurityCampaigns::ManagersDependency
  extend T::Helpers

  requires_ancestor { ApplicationController }

  sig { params(org: Organization).returns(T.any(T::Array[User], String)) }
  def prepare_managers(org)
    manager_ids = Array.wrap(params[:campaign_managers]).compact_blank.uniq.map(&:to_i)
    managers = User.where(id: manager_ids).index_by(&:id)
    potential_campaign_managers = SecurityCampaigns.potential_campaign_managers(org:)
    manager_ids.map do |id|
      manager = managers[id]
      return render status: 404, json: { message: "Campaign manager not found" } unless manager
      return render status: 422, json: { message: "Campaign manager must be a security manager of this organization" } unless potential_campaign_managers.include?(manager)
      manager
    end
  end

  sig { params(org: Organization).returns(T.any(T::Array[Team], String)) }
  def prepare_team_managers(org)
    team_manager_ids = Array.wrap(params[:team_managers]).compact_blank.uniq.map(&:to_i)
    teams = Team.where(organization: org, id: team_manager_ids).index_by(&:id)
    potential_campaign_manager_teams = SecurityCampaigns.potential_campaign_manager_teams(org:, current_user:)

    team_managers = team_manager_ids.map do |slug|
      team = teams[slug]
      return render status: 404, json: { message: "Campaign team manager not found" } unless team
      return render status: 422, json: { message: "Campaign team manager must be a security team of this organization" } unless potential_campaign_manager_teams.include?(team)

      team
    end
  end

  sig { params(user_manager_ids: T::Array[String], team_manager_ids: T::Array[String]).returns(T.nilable(String)) }
  def validate_number_campaign_managers(user_manager_ids:, team_manager_ids:)
    if (team_manager_ids + user_manager_ids).size < 1
      return render status: 422, json: { message: SecurityCampaigns::MIN_CAMPAIGN_MANAGER_ERROR_MESSAGE }
    end
    if (team_manager_ids + user_manager_ids).size > SecurityCampaigns::MAX_MANAGER_COUNT
      render status: 422, json: { message: SecurityCampaigns::MAX_CAMPAIGN_MANAGER_ERROR_MESSAGE }
    end
  end
end
