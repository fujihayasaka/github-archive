# typed: true
# frozen_string_literal: true

class Stafftools::Users::Billing::PolicyController < Stafftools::Users::BillingController
  include ApplicationController::VerifiedFetchDependency
  include GitHub::Memoizer
  include Billing::PoliciesDependency

  allow_verified_fetch only: [:update]

  sig { void }
  def update
    overage_policy_type = params[:type]
    overage_policy_name = params[:name]
    overage_policy_enabled = params[:enabled]
    success = update_policy_request(this_entity: this_user, overage_policy_type: overage_policy_type, overage_policy_name: overage_policy_name, overage_policy_enabled: overage_policy_enabled)

    if success
      flash[:notice] = "Overage policy updated successfully."
    else
      flash[:error] = "Failed to update overage policy."
    end

    if params[:return_to].present?
      safe_redirect_to return_to
    else
      render json: { message: "Overage policy scheduled to update." }, status: :ok
    end
  end
end
