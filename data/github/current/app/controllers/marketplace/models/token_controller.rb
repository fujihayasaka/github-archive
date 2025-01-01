# typed: true
# frozen_string_literal: true

class Marketplace::Models::TokenController < ApplicationController
  include MarketplaceHelper
  include Marketplace::Models::PlaygroundDependency
  include ApplicationController::VerifiedFetchDependency

  before_action :login_required
  before_action :github_models_required
  before_action :require_neutron_playground_enabled
  allow_verified_fetch only: [:create]

  def create
    render json: generate_oauth_token(user_session)
  end

  private

  def require_neutron_playground_enabled
    access_result = GitHubModels::PlaygroundAccessResult.for(current_user)
    unless access_result.accessible?
      render json: { error: human_readable_reason(access_result.reason) }, status: 404
    end
  end

  def target_for_conditional_access
    # If the user is not logged in, we return a 401 (:login_required)
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end
end
