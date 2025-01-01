# typed: true
# frozen_string_literal: true

module Businesses::PersonalAccessTokenPolicies
  class MaximumLifetimesController < Businesses::BusinessController
    include ControllerMethods

    before_action :business_owner_required
    before_action :require_feature_flags
    before_action :sudo_filter

    def update
      if require_pat_to_expire_enabled?
        type, message = set_maximum_lifetime_configuration(this_business, current_user, pat_type, access_token_expiration_limit, exempt_administrators?)
      else
        type, message = disable_maximum_lifetime_configuration(this_business, current_user, pat_type)
      end

      flash[type] = message

      if pat_type == ProgrammaticAccessTokenType::Classic && this_business.feature_enabled?(:pat_policies_page_redesign)
        redirect_to settings_classic_personal_access_tokens_enterprise_path(this_business)
      else
        redirect_to settings_personal_access_tokens_enterprise_path(this_business)
      end
    rescue KeyError
      flash[:error] = "Invalid Personal Access Token type"
      redirect_to settings_personal_access_tokens_enterprise_path(this_business)
    end

    private

    def access_token_expiration_limit
      params[:business][:fine_grained_personal_access_token_expiration_limit] == "custom" ? params[:business][:custom_fine_grained_personal_access_token_expiration_limit].to_i : params[:business][:fine_grained_personal_access_token_expiration_limit].to_i
    end

    def require_pat_to_expire_enabled?
      params[:business][:require_pat_to_expire] == "1"
    end

    def exempt_administrators?
      params[:business][:exempt_administrators] == "1"
    end

    def pat_type
      ProgrammaticAccessTokenType.deserialize(params[:business][:pat_type])
    end

    def require_feature_flags
      render_404 unless this_business.feature_enabled?(:personal_access_token_expiration_limit)
    end
  end
end
