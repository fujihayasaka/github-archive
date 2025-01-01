# typed: strict
# frozen_string_literal: true

module Orgs::Settings::ThirdPartyAccess::PersonalAccessTokens
  class OwnersController < Orgs::Controller
    extend T::Sig

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

    helper_method :total_pages

    PAGE_SIZE = 1000

    sig { returns(T.untyped) }
    def index
      users = users_with_grants_on_org_paginated_and_sorted

      render partial: "orgs/settings/third_party_access/personal_access_tokens/filters/owners_content",
        layout: false,
        locals: {
          selected_owner: fetch_from_filter(current_organization, "owner", params[:q]),
          users: users,
          total_pages: users.try(:total_pages) || 1
        }
    end

    private

    sig { returns(T.untyped) }
    def require_feature_flags
      render_404 unless current_organization.patsv2_enabled?
    end

    sig { returns(ActiveRecord::Relation) }
    def users_with_grants_on_org_paginated_and_sorted
      user_ids = ProgrammaticAccessGrant.
        with_target(current_organization).
        joins(:user_programmatic_access).
        distinct.
        pluck("user_programmatic_accesses.user_id")

      User.where(id: user_ids).order(login: :asc).paginate(page: 1, per_page: PAGE_SIZE)
    end
  end
end
