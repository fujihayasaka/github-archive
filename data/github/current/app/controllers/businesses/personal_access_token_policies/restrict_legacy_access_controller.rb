# typed: true
# frozen_string_literal: true

module Businesses::PersonalAccessTokenPolicies
  class RestrictLegacyAccessController < Businesses::BusinessController
    include ControllerMethods

    before_action :business_owner_required
    before_action :require_feature_flags
    before_action :sudo_filter

    def update
      type, message = set_restrict_legacy_access_configuration(this_business, current_user, filtered_params)
      flash[type] = message

      redirect_to settings_classic_personal_access_tokens_enterprise_path(this_business)
    end

    private

    def filtered_params
      params.require(:business).permit(:restrict_legacy_access)
    end

    def require_feature_flags
      render_404 unless this_business.patsv2_enabled?
    end
  end
end
