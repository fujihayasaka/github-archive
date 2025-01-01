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
    response = ActiveRecord::Base.connected_to(role: :reading) do
      SecurityCampaigns.potential_campaign_managers(org: this_organization).map do |manager|
        {
          id: manager.id,
          login: manager.display_login,
          avatarUrl: manager.primary_avatar_url(40),
        }
      end.uniq
    end

    render json: { managers: response }
  end
end
