# typed: strict
# frozen_string_literal: true

module Orgs::Settings::ThirdPartyAccess::PersonalAccessTokens
  class PermissionsController < Orgs::Controller
    include PersonalAccessTokensControllerHelper

    depends_on_clusters ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Permissions,
    ApplicationRecord::Repositories

    depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

    before_action :organization_admin_required
    before_action :ensure_trade_restrictions_allows_org_settings_access
    before_action :require_feature_flags

    sig { returns(T.untyped) }
    def index
      render partial: "orgs/settings/third_party_access/personal_access_tokens/filters/permissions_content",
        layout: false,
        locals: {
          selected_permission: fetch_from_filter(current_organization, "permission", params[:q]),
          access: ProgrammaticAccess.new_access(current_user)
        }
    end

    private

    sig { returns(T.untyped) }
    def require_feature_flags
      render_404 unless current_organization.patsv2_enabled?
    end
  end
end
