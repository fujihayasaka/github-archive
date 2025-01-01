# typed: true
# frozen_string_literal: true

class Orgs::SecurityCenter::SecurityCampaignsManagersController < Orgs::SecurityCenter::AbstractSecurityCampaignsController
  extend T::Sig

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Iam,
    ApplicationRecord::Configurations,
    only: [:index]

  def index
    response = ActiveRecord::Base.connected_to(role: :reading) do
      potential_campaign_managers = this_organization.admins + SecurityProduct::SecurityManagers.new(this_organization).teams.map(&:members).flatten
      potential_campaign_managers.map do |manager|
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
