# typed: true
# frozen_string_literal: true

module Orgs::Settings::ThirdPartyAccess::PersonalAccessTokens
  class RepositorySelectionController < Orgs::Controller
    before_action :organization_admin_required
    before_action :ensure_trade_restrictions_allows_org_settings_access
    before_action :require_feature_flags
    before_action :current_grant_required

    depends_on_clusters ApplicationRecord::Collab,
      ApplicationRecord::Configurations,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Mysql1,
      ApplicationRecord::Mysql2,
      ApplicationRecord::Mysql5,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Permissions,
      ApplicationRecord::Repositories,
     only: [:index]

    depends_on_clusters ApplicationRecord::Copilot,
      only: [:index],
      optional: true

    javascript_bundle :settings

    def index
      render ProgrammaticAccess::RepositorySelection::ListComponent.new(
        current_grant, controller: controller_name, action: action_name,
        page: current_page, repositories_path: org_person_path(current_organization, current_grant.user_programmatic_access.owner)
      ), layout: false
    end

    private

    def current_grant
      ProgrammaticAccessGrant.from_target_and_id(current_organization, params[:id])
    end

    def current_grant_required
      render_404 unless current_grant
    end

    def require_feature_flags
      render_404 unless current_organization.patsv2_enabled?
    end
  end
end
