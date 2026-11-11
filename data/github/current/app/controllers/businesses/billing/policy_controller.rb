# typed: strict
# frozen_string_literal: true

class Businesses::Billing::PolicyController < Businesses::BillingsController
  before_action :business_access_required

  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include Billing::Platform::Api::Utils
  include Billing::PoliciesDependency

  allow_verified_fetch only: [:update]
  before_action :parse_json_params, only: [:update]

  sig { void }
  def update
    # Support batch updates via policies array param, or single update via type/name/enabled params
    if params.key?(:policies)
      update_multiple_policies
    else
      update_single_policy
    end
  end

  private

  sig { void }
  def update_single_policy
    overage_policy_type = params[:type]
    overage_policy_name = params[:name]
    overage_policy_enabled = params[:enabled]
    success = update_policy_request(this_entity: this_business, overage_policy_type: overage_policy_type, overage_policy_name: overage_policy_name, overage_policy_enabled: overage_policy_enabled)

    if success
      flash[:notice] = "Overage policy updated successfully."
    else
      flash[:error] = "Failed to update overage policy."
    end

    handle_redirect(overage_policy_name, params[:enabled])
  end

  sig { void }
  def update_multiple_policies
    policies = params[:policies]
    unless policies.is_a?(Array)
      render json: { error: "Invalid policies parameter" }, status: :unprocessable_entity
      return
    end

    results = policies.map do |policy|
      policy_type = policy[:type] || policy["type"]
      policy_name = policy[:name] || policy["name"]
      policy_enabled = policy[:enabled] || policy["enabled"]

      next { name: policy_name, success: false, error: "Missing required fields" } if policy_type.blank? || policy_name.blank? || policy_enabled.nil?

      success = update_policy_request(
        this_entity: this_business,
        overage_policy_type: policy_type,
        overage_policy_name: policy_name,
        overage_policy_enabled: policy_enabled.to_s
      )

      { name: policy_name, success: success, enabled: policy_enabled.to_s }
    end

    all_successful = results.empty? || results.all? { |r| r[:success] }
    enabled = results.empty? ? false : results.all? { |r| r[:enabled] == "true" }

    if all_successful
      flash[:notice] = "All overage policies updated successfully."
    else
      failed_policies = results.reject { |r| r[:success] }.map { |r| r[:name] }.join(", ")
      flash[:error] = "Failed to update some overage policies: #{failed_policies}"
    end

    handle_redirect(nil, enabled.to_s)
  end

  sig { params(policy_name: T.nilable(String), enabled: T.nilable(String)).void }
  def handle_redirect(policy_name, enabled)
    if params[:return_to].present?
      uri = URI.parse(params[:return_to])

      # Remove all existing query parameters for a clean set
      uri.query = nil
      query = {}

      # Add overages key for single policy update or all for a multi policy update
      # We do this wonky workaround because this will reload before the backend
      # changes with an asynchronous job, so this makes the state match what
      # users expect.
      if policy_name.present?
        overages_key = "overages-#{policy_name}"
        query[overages_key] = enabled
      else
        query["overages-all"] = enabled
      end

      uri.query = Rack::Utils.build_query(query)
      return_to = uri.to_s

      safe_redirect_to return_to
    else
      render json: { message: "Overage policy updated successfully." }, status: :ok
    end
  end
end
