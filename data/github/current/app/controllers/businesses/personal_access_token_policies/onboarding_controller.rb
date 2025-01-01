# typed: true
# frozen_string_literal: true

module Businesses::PersonalAccessTokenPolicies
  class OnboardingController < Businesses::BusinessController
    include ControllerMethods
    include ::Businesses::PersonalAccessTokenRequestPolicies::ControllerMethods

    class ConfigurationError < StandardError; end

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Configurations,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Collab,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Repositories,
      ApplicationRecord::Billing,
      only: [:edit]

    depends_on_clusters ApplicationRecord::Copilot,
      only: [:edit], optional: true

    before_action :business_owner_required
    before_action :require_feature_flags
    before_action :business_full_plan_required

    def edit
      render "businesses/personal_access_token_policies/onboarding/edit"
    end

    def update # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
      ApplicationRecord::Domain::ConfigurationEntries.transaction do
        begin
          flash_type, message = set_restrict_access_configuration(this_business, current_user, filtered_params)
          raise_on_error(flash_type, message)

          flash_type, message = set_pat_request_auto_approvals_configuration(this_business, current_user, filtered_params)
          raise_on_error(flash_type, message)

          flash_type, message = set_restrict_legacy_access_configuration(this_business, current_user, filtered_params)
          raise_on_error(flash_type, message)

          this_business.opt_in_programmatic_access_tokens(actor: current_user)
        rescue ConfigurationError => exception
          @exception = exception
          raise ActiveRecord::Rollback
        end
      end

      if defined?(@exception)
        GitHub.dogstats.increment("business.pats.onboard", tags: ["status:failed"])
        return render json: { message: @exception.message }, status: :conflict
      end

      GitHub.dogstats.increment("business.pats.onboard", tags: ["status:success"])
      head :no_content unless defined?(@exception)
    end

    private

    def filtered_params
      params.require(:business).permit(:restrict_access, :pat_auto_approvals, :restrict_legacy_access)
    end

    def raise_on_error(flash_type, message)
      return unless flash_type == :error
      raise ConfigurationError, message
    end

    def require_feature_flags
      return render_404 unless current_user.patsv2_enabled?
      return unless this_business.patsv2_enabled?

      redirect_to settings_personal_access_tokens_enterprise_path(this_business)
    end
  end
end
