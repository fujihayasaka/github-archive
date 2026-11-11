# typed: strict
# frozen_string_literal: true

class Customers::Billing::PolicyController < Customers::BillingController
  include Billing::Platform::Api::Utils
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include Billing::PoliciesDependency

  before_action :login_required
  before_action :parse_json_params, only: [:update]
  allow_verified_fetch only: [:update]

  sig { void }
  def update
    # Support batch updates via policies array param, or single update via type/name/enabled params
    policies = params[:policies]
    if policies.present? || policies.is_a?(Array)
      update_multiple_policies(policies)
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
    success = update_policy_request(this_entity: this_entity, overage_policy_type: overage_policy_type, overage_policy_name: overage_policy_name, overage_policy_enabled: overage_policy_enabled)

    notice = success ? "Overage policy updated successfully." : nil
    error_msg = success ? nil : "Failed to update overage policy."

    handle_response(policy_name: overage_policy_name, enabled: params[:enabled], notice: notice, error_msg: error_msg)
  end

  sig { params(policies: T.untyped).void }
  def update_multiple_policies(policies)
    if !policies.is_a?(Array) || policies.empty?
      return render json: { error: "Invalid policies parameter" }, status: :unprocessable_entity
    end

    results = policies.map do |policy|
      policy_type = policy[:type] || policy["type"]
      policy_name = policy[:name] || policy["name"]
      policy_enabled = policy[:enabled] || policy["enabled"]

      next { name: policy_name, success: false, error: "Missing required fields" } if policy_type.blank? || policy_name.blank? || policy_enabled.nil?

      success = update_policy_request(
        this_entity: this_entity,
        overage_policy_type: policy_type,
        overage_policy_name: policy_name,
        overage_policy_enabled: policy_enabled.to_s
      )

      { name: policy_name, success: success, enabled: policy_enabled }
    end

    all_successful = results.empty? || results.all? { |r| r[:success] }
    enabled = results.empty? ? false : results.all? { |r| ActiveModel::Type::Boolean.new.cast(r[:enabled]) }

    notice = all_successful ? "All overage policies updated successfully." : nil
    failed_policies = results.reject { |r| r[:success] }.map { |r| r[:name] }.join(", ")
    error_msg = all_successful ? nil : "Failed to update some overage policies: #{failed_policies}"

    handle_response(policy_name: nil, enabled: enabled.to_s, notice: notice, error_msg: error_msg)
  end

  sig { params(policy_name: T.nilable(String), enabled: T.nilable(String), notice: T.nilable(String), error_msg: T.nilable(String)).void }
  def handle_response(policy_name:, enabled:, notice:, error_msg:)
    if params[:return_to].present?
      # Set flash only when redirecting (ViewComponent path).
      # React callers receive feedback via the JSON response instead.
      flash[:notice] = notice if notice.present?
      flash[:error] = error_msg if error_msg.present?

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
      if error_msg.present?
        render json: { error: error_msg }, status: :unprocessable_entity
      else
        render json: { message: notice || "Overage policy updated successfully." }, status: :ok
      end
    end
  end
end
