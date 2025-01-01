# typed: true
# frozen_string_literal: true

class Businesses::TermsOfServiceController < Businesses::BusinessController

  before_action :dotcom_required
  before_action :login_required
  before_action :business_access_required

  def update
    return render_404 unless this_business.feature_enabled?(:business_on_standard_tos)
    return render_404 unless this_business.terms_of_service_type == "Standard"

    if params[:gca_checkbox].blank?
      flash[:error] = "You must agree to the Customer Agreement."
      return redirect_to :back
    end

    this_business.update!(terms_of_service_type: "Corporate")
    redirect_to :back, notice: "Terms of service updated!"
  end
end
