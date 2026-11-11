# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::ModelsBillingController < Stafftools::Businesses::BusinessBaseController
  include GitHubModels::BillingDependency

  sig { void }
  def create
    respond_to do |format|
      format.turbo_stream do
        if params[:enable_models_billing] == "on"
          this_business.enable_models_billing(current_user)
        elsif params[:enable_models_billing] == "off"
          this_business.disable_models_billing(current_user)
        end

        render "github_models/businesses/models_billing/create", locals: {
          billing_enabled: this_business.models_billing_enabled?,
          business: this_business,
        }, layout: false
      end
    end
  end
end
