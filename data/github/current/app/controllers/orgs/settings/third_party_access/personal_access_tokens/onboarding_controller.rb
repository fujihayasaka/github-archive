# typed: true
# frozen_string_literal: true

module Orgs::Settings::ThirdPartyAccess::PersonalAccessTokens
  class OnboardingController < Orgs::Controller
    DISABLE      = "disable"

    CONFIGURABLE_EXCEPTIONS = [
      Configurable::AutoApprovePersonalAccessTokenGrantRequests::AutoApprovalRestrictedError,
      Configurable::RestrictPersonalAccessTokens::ConfigurationError,
      Configurable::RestrictLegacyPersonalAccessTokens::ConfigurationError,
      Configurable::ProgrammaticAccessTokensOptIn::ConfigurationError,
    ]

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Configurations,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Collab,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Repositories,
      ApplicationRecord::Billing,
      ApplicationRecord::Copilot,
      only: [:edit]

    before_action :organization_admin_required
    before_action :ensure_trade_restrictions_allows_org_settings_access
    before_action :require_feature_flags
    before_action :ensure_not_previously_enrolled

    helper_method :pats_restricted_by_policy?, :pats_enforced_by_policy?, :pats_allowed?, :pats_not_allowed?

    def edit
      render "orgs/settings/third_party_access/personal_access_tokens/onboarding/edit"
    end

    def update # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
      ApplicationRecord::Domain::ConfigurationEntries.transaction do
        begin
          toggle_restriction!
          toggle_auto_approval!
          toggle_legacy_restriction!

          current_organization.opt_in_programmatic_access_tokens(actor: current_user)
        rescue *CONFIGURABLE_EXCEPTIONS => exception
          @exception = exception
          raise ActiveRecord::Rollback
        end
      end

      if defined?(@exception)
        GitHub.dogstats.increment("organization.pats.onboard", tags: ["status:failed"])
        return render json: { message: @exception.message }, status: :conflict
      end

      GitHub.dogstats.increment("organization.pats.onboard", tags: ["status:success"])
      head :no_content unless defined?(@exception)
    end

    private

    def enable?(key)
      onboarding_params[key] != DISABLE
    end

    def ensure_not_previously_enrolled
      return unless current_organization.patsv2_enabled?
      redirect_to settings_org_personal_access_tokens_path(current_organization)
    end

    def onboarding_params
      params.require(:organization).permit(:auto_approve, :restrict_access, :restrict_legacy_access)
    end

    def require_feature_flags
      render_404 unless current_user.patsv2_enabled?
    end

    def toggle_auto_approval!
      method = enable?(:auto_approve) ? :enable_auto_pat_request_approval : :disable_auto_pat_request_approval
      current_organization.public_send(method, actor: current_user)
    end

    def toggle_restriction!
      method = enable?(:restrict_access) ? :restrict_personal_access_tokens : :permit_personal_access_tokens
      current_organization.public_send(method, actor: current_user)
    end

    def toggle_legacy_restriction!
      method = enable?(:restrict_legacy_access) ? :restrict_legacy_personal_access_tokens : :permit_legacy_personal_access_tokens
      current_organization.public_send(method, actor: current_user)
    end

    memoize def pats_restricted_by_policy?
      current_organization.personal_access_tokens_restricted_policy?
    end

    memoize def pats_enforced_by_policy?
      current_organization.personal_access_tokens_enforced_policy?
    end

    memoize def pats_allowed?
      pats_enforced_by_policy? || current_organization.personal_access_tokens_allowed?
    end

    def pats_not_allowed?
      pats_restricted_by_policy? || !pats_allowed?
    end
  end
end
