# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::ExternalProviderController < Stafftools::Businesses::BusinessBaseController
  before_action :external_provider_required

  def destroy
    if params[:reason].blank?
      flash[:error] = "You must provide a reason for the log."
    else
      event = this_business.saml_provider ? "staff.delete_business_saml_provider" : "staff.delete_business_oidc_provider"

      this_business.external_provider.destroy
      flash[:notice] = "SSO was disabled."

      instrument event, business: this_business, note: params[:reason]
    end

    redirect_to stafftools_enterprise_security_path(this_business)
  end

  private

  def external_provider_required
    render_404 unless this_business.external_provider.present?
  end
end
