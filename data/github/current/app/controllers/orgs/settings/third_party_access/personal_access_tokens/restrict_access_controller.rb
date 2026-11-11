# typed: true
# frozen_string_literal: true

module Orgs::Settings::ThirdPartyAccess::PersonalAccessTokens
  class RestrictAccessController < Orgs::Controller
    before_action :organization_admin_required
    before_action :ensure_trade_restrictions_allows_org_settings_access
    before_action :require_feature_flags
    before_action :sudo_filter

    javascript_bundle :settings

    def update
      begin
        toggle_restriction!
      rescue Configurable::RestrictPersonalAccessTokens::ConfigurationError => e
        flash[:error] = e.message
      end

      flash[:notice] = successful_update_message unless flash.key?(:error)
      redirect_to settings_org_personal_access_tokens_path(current_organization)
    end

    private

    def enable?
      filtered_params[:restrict_access] != "disable"
    end

    def filtered_params
      params.require(:organization).permit(:restrict_access)
    end

    def require_feature_flags
      render_404 unless current_organization.patsv2_enabled?
    end

    def successful_update_message
      return "Personal access tokens are no longer able to access your organization." if enable?

      "Personal access tokens are now able to access your organization."
    end

    def toggle_restriction!
      method = enable? ? :restrict_personal_access_tokens : :permit_personal_access_tokens
      current_organization.public_send(method, actor: current_user)
    end
  end
end
