# typed: true
# frozen_string_literal: true

module Orgs::Settings::ThirdPartyAccess::PersonalAccessTokenRequests
  class AutoApproveController < Orgs::Controller
    before_action :organization_admin_required
    before_action :ensure_trade_restrictions_allows_org_settings_access
    before_action :require_feature_flags
    before_action :sudo_filter

    javascript_bundle :settings

    def update
      begin
        toggle_auto_approval!
      rescue Configurable::AutoApprovePersonalAccessTokenGrantRequests::AutoApprovalRestrictedError => e
        flash[:error] = e.message
      end

      flash[:notice] = successful_update_message unless flash.key?(:error)
      redirect_to settings_org_personal_access_tokens_path(current_organization)
    end

    private

    def enable?
      filtered_params[:auto_approve] != "disable"
    end

    def filtered_params
      params.require(:organization).permit(:auto_approve)
    end

    def require_feature_flags
      render_404 unless current_organization.patsv2_enabled?
    end

    def successful_update_message
      return "All fine-grained personal access tokens requested for this organization will work immediately" if enable?

      "All organization fine-grained personal access token requests are now subject to administrator review."
    end

    def toggle_auto_approval!
      method = enable? ? :enable_auto_pat_request_approval : :disable_auto_pat_request_approval
      current_organization.public_send(method, actor: current_user)
    end
  end
end
