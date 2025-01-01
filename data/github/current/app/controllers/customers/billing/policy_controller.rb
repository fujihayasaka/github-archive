# typed: strict
# frozen_string_literal: true

class Customers::Billing::PolicyController < Customers::BillingController
  include Billing::Platform::Api::Utils
  include ApplicationController::VerifiedFetchDependency
  include Billing::PoliciesDependency

  before_action :login_required
  allow_verified_fetch only: [:update]

  sig { void }
  def update
    overage_policy_type = params[:type]
    overage_policy_name = params[:name]
    overage_policy_enabled = params[:enabled]
    success = update_policy_request(this_entity: this_entity, overage_policy_type: overage_policy_type, overage_policy_name: overage_policy_name, overage_policy_enabled: overage_policy_enabled)

    if success
      flash[:notice] = "Overage policy updated successfully."
    else
      flash[:error] = "Failed to update overage policy."
    end

    if params[:return_to].present?
      safe_redirect_to params[:return_to]
    else
      render json: { message: "Overage policy updated successfully." }, status: :ok
    end
  end
end
