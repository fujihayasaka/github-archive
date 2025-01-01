# typed: true
# frozen_string_literal: true

class Marketplace::Models::TokenController < ApplicationController
  extend T::Sig
  include MarketplaceHelper
  include Marketplace::Models::PlaygroundDependency
  include ApplicationController::VerifiedFetchDependency

  before_action :marketplace_required
  before_action :require_neutron_playground_enabled
  allow_verified_fetch only: [:create]

  def create
    render json: generate_oauth_token(user_session)
  end

  private

  def require_neutron_playground_enabled
    render_404 unless check_playground_access.accessible?
  end

  def target_for_conditional_access
    current_user
  end
end
