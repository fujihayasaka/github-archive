# typed: strict
# frozen_string_literal: true

class Businesses::Billing::PolicyController < Businesses::BillingsController
  before_action :business_access_required

  include ApplicationController::VerifiedFetchDependency
  include Billing::Platform::Api::Utils
  include Billing::PoliciesDependency

  allow_verified_fetch only: [:update]

  sig { void }
  def update
    overage_policy_type = params[:type]
    overage_policy_name = params[:name]
    overage_policy_enabled = params[:enabled]
    success = update_policy_request(this_entity: this_business, overage_policy_type: overage_policy_type, overage_policy_name: overage_policy_name, overage_policy_enabled: overage_policy_enabled)

    if success
      flash[:notice] = "Overage policy updated successfully."
    else
      flash[:error] = "Failed to update overage policy."
    end

    if params[:return_to].present?
      uri = URI.parse(params[:return_to])
      query = Rack::Utils.parse_nested_query(uri.query)
      query["overages"] = params[:enabled]
      uri.query = Rack::Utils.build_query(query)
      return_to = uri.to_s

      safe_redirect_to return_to
    else
      render json: { message: "Overage policy updated successfully." }, status: :ok
    end
  end
end
