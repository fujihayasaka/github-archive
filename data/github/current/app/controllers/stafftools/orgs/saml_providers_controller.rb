# typed: true
# frozen_string_literal: true

class Stafftools::Orgs::SamlProvidersController < StafftoolsController # rubocop:todo GitHub/ControllersShouldHaveTests
  before_action :ensure_saml_enabled

  layout "layouts/stafftools/user/security"

  def destroy
    reason = params[:reason]

    if reason.blank?
      flash[:error] = "You must provide a reason for the log."
    else
      this_user.saml_provider.destroy(reason)
      flash[:notice] = "SAML SSO disabled for #{this_user}."
    end

    redirect_to :back
  end

  private

  def ensure_saml_enabled
    render_404 unless this_user.organization? && this_user.saml_provider.present?
  end
end
