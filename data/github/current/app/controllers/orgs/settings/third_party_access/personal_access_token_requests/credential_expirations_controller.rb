# typed: strict
# frozen_string_literal: true

module Orgs::Settings::ThirdPartyAccess::PersonalAccessTokenRequests
  class CredentialExpirationsController < Orgs::Controller
    extend T::Sig

    before_action :organization_admin_required
    before_action :ensure_trade_restrictions_allows_org_settings_access
    before_action :require_feature_flags
    before_action :ensure_current_grant_request
    before_action :ensure_current_access

    javascript_bundle :settings

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Configurations,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Collab,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Repositories,
      ApplicationRecord::Billing,
      ApplicationRecord::Permissions

    depends_on_clusters ApplicationRecord::Copilot,
      only: [:show],
      optional: true

    sig { void }
    def show
      expiration_result = ProgrammaticAccessToken.expiration_for(current_access)
      return head :service_unavailable if expiration_result.failed?

      render PersonalAccessTokens::ExpirationInfoComponent.new(expiration_time: expiration_result.value), layout: false
    end

    private

    sig { returns(T.nilable(ProgrammaticAccessGrantRequest::ORGANIZATION_TYPE)) }
    def current_grant_request
      ProgrammaticAccessGrantRequest.with_target(current_organization).preload(:user_programmatic_access).find_by(id: params[:id])
    end

    sig { returns(T.nilable(ProgrammaticAccess::USER_TYPE)) }
    def current_access
      current_grant_request&.user_programmatic_access
    end

    sig { void }
    def ensure_current_grant_request
      render_404 unless current_grant_request
    end

    sig { void }
    def ensure_current_access
      render_404 unless current_access
    end

    sig { void }
    def require_feature_flags
      render_404 unless current_organization.patsv2_enabled?
    end
  end
end
