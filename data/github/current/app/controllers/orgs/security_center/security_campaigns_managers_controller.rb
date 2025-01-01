# typed: true
# frozen_string_literal: true

class Orgs::SecurityCenter::SecurityCampaignsManagersController < Orgs::SecurityCenter::AbstractSecurityCampaignsController

  before_action :manage_security_products_permission_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Iam,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    only: [:index]

  def index
    user_managers = ActiveRecord::Base.connected_to(role: :reading) do
      SecurityCampaigns.potential_campaign_managers(org: this_organization).map do |manager|
        {
          id: manager.id,
          login: manager.display_login,
          name: manager.profile_name,
          avatarUrl: manager.primary_avatar_url(40),
        }
      end.uniq
    end

    team_managers = ActiveRecord::Base.connected_to(role: :reading) do
      teams = SecurityCampaigns.potential_campaign_manager_teams(org: this_organization, current_user:)
      GitHub::PrefillAssociations.prefill_associations(teams, :organization, available_records: [this_organization])
      teams.map do |team|
        {
          id: team.id,
          slug: team.slug,
          name: team.name,
          avatarUrl: team.primary_avatar_url(40),
          organizationLogin: team.organization&.display_login,
        }
      end.uniq
    end

    render json: { managers: user_managers, teamManagers: team_managers }
  end
end
