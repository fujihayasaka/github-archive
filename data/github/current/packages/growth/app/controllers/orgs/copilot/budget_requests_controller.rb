# typed: strict
# frozen_string_literal: true

class Orgs::Copilot::BudgetRequestsController < Orgs::Controller
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency

  before_action :login_required
  before_action :member_requests_available_required
  before_action :ensure_feature_flag_enabled
  before_action :ensure_org_member
  before_action :parse_json_params, only: [:create]

  allow_verified_fetch only: [:create, :destroy]

  sig { void }
  def create
    amount_cents = validate_requested_amount
    return if performed?

    billing_entity = this_organization.business || this_organization

    member_request = MemberFeatureRequest.find_or_initialize_by(
      requester: current_user,
      request_entity: this_organization,
      billing_entity: billing_entity,
      feature: MemberFeatureRequest::Feature::CopilotPremiumRequestBudget,
    )
    member_request.request_type = :additional_budget
    member_request.status = :requested
    member_request.requested_amount_cents = amount_cents

    if member_request.save
      update_request_state_cache("post_request")
      render json: { message: "Your request for additional budget has been submitted." }, status: :ok
    else
      render json: { error: member_request.errors.full_messages }, status: :unprocessable_entity
    end
  end

  sig { void }
  def destroy
    billing_entity = this_organization.business || this_organization

    member_request = MemberFeatureRequest.find_by(
      requester: current_user,
      request_entity: this_organization,
      billing_entity: billing_entity,
      feature: MemberFeatureRequest::Feature::CopilotPremiumRequestBudget,
    )

    if member_request.nil?
      head :not_found
      return
    end

    if member_request.destroy
      clear_request_state_cache
      render json: { message: "Your budget request has been removed." }, status: :ok
    else
      render json: { error: member_request.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  sig { void }
  def member_requests_available_required
    render_404 if MemberFeatureRequest.unavailable?(user: current_user)
  end

  sig { void }
  def ensure_feature_flag_enabled
    head(:not_found) unless FeatureFlag.vexi.enabled?(:copilot_budget_request_cta, current_user, default: false)
  end

  sig { void }
  def ensure_org_member
    unless this_organization.direct_or_team_member?(current_user)
      head :forbidden
    end
  end

  sig { returns(T.nilable(Integer)) }
  def validate_requested_amount
    raw = params[:requested_amount_cents]

    begin
      amount = Integer(raw)
    rescue ArgumentError, TypeError
      render json: { error: "requested_amount_cents must be a positive integer" }, status: :unprocessable_entity
      return nil
    end

    if amount <= 0
      render json: { error: "requested_amount_cents must be a positive integer" }, status: :unprocessable_entity
      return nil
    end

    if amount > MemberFeatureRequest::MAX_REQUESTED_AMOUNT_CENTS
      render json: { error: "requested_amount_cents must not exceed #{MemberFeatureRequest::MAX_REQUESTED_AMOUNT_CENTS}" }, status: :unprocessable_entity
      return nil
    end

    amount
  end

  sig { params(state: String, declined_date: T.nilable(String)).void }
  def update_request_state_cache(state, declined_date: nil)
    payload = { "state" => state, "declined_date" => declined_date }
    client = Copilot::Cache::BudgetRequestStateClient.new(
      user_id: current_user.id,
      org_id: this_organization.id,
    )
    client.store(payload)
  rescue StandardError
    # best-effort cache update; banner will show stale state until TTL expires
  end

  sig { void }
  def clear_request_state_cache
    client = Copilot::Cache::BudgetRequestStateClient.new(
      user_id: current_user.id,
      org_id: this_organization.id,
    )
    client.invalidate
  rescue StandardError
    # best-effort
  end
end
