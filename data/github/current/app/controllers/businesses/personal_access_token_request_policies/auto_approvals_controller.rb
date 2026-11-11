# typed: true
# frozen_string_literal: true

module Businesses::PersonalAccessTokenRequestPolicies
  class AutoApprovalsController < Businesses::BusinessController
    include ControllerMethods

    before_action :business_owner_required
    before_action :require_feature_flags
    before_action :sudo_filter

    def update
      type, message = set_pat_request_auto_approvals_configuration(this_business, current_user, filtered_params)

      flash[type] = message
      redirect_to settings_personal_access_tokens_enterprise_path(this_business)
    end

    private

    def filtered_params
      params.require(:business).permit(:pat_auto_approvals)
    end

    def require_feature_flags
      render_404 unless this_business.patsv2_enabled?
    end
  end
end
