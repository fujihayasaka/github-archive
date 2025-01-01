# typed: true
# frozen_string_literal: true

class IntegrationInstallationRequestsController < ApplicationController

  # We can safely skip the `perform_conditional_access_checks` filter
  # for the following actions:
  # - destroy: does not access the target organization.
  #
  # rubocop:disable GitHub/DoNotSkipCapBeforeAction
  skip_before_action :perform_conditional_access_checks, only: %w(destroy)

  before_action :require_integration
  before_action :require_integration_installation_request
  before_action :require_authorized_request_actor

  stylesheet_bundle :integrations

  # Removes an IntegrationInstallationRequest. Can only be performed by the
  # original issuer of the request, or by an owner of the target Organization.
  def destroy
    installation_request = current_integration_installation_request

    reason = installation_request.requester == current_user ? :canceled : :rejected

    unless installation_request.close(reason: reason, actor: current_user)
      redirect_to gh_new_app_installation_url(current_integration, current_user),
        notice: "The installation request could not be canceled. Please try again."
      return
    end

    to = request.referrer || gh_new_app_installation_url(current_integration, current_user)
    safe_redirect_to to, notice: "The installation request has been canceled."
  end

  private

  def current_integration # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @integration ||= Integration.from_owner_and_slug!(
      viewer:        current_user,
      slug:          params[:integration_id],
      user_login:    params[:owner],
      business_slug: params[:slug],
    )
  end

  def require_integration
    render_404 unless current_integration.present?
  end

  def current_integration_installation_request # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @installation_request ||= IntegrationInstallationRequest.find_by(
      id: params[:request_id],
      integration_id: current_integration.id,
    )
  end

  def require_integration_installation_request
    render_404 unless current_integration_installation_request.present?
  end

  def require_authorized_request_actor
    return if current_integration_installation_request.requester == current_user
    return if current_integration_installation_request.target.adminable_by?(current_user)
    render_404
  end
end
