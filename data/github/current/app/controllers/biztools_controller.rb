# typed: true
# frozen_string_literal: true

class BiztoolsController < ApplicationController

  before_action :ensure_billing_enabled
  before_action :login_required
  before_action :require_admin_frontend
  before_action :sudo_filter
  before_action :biztools_only
  skip_before_action :cap_pagination
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  layout "layouts/biztools"
  javascript_bundle "biztools"
  stylesheet_bundle "biztools"

  private

  # Find the current user from the route
  #
  # user - The login name of the user in question
  memoize def current_account
    login = params[:user_id]
    User.where(type: %w[User Organization]).find_by(login: login)
  end
  helper_method :current_account

  # Find the current business from the route
  memoize def current_business
    slug = params[:slug]
    Business.find_by(slug: slug)
  end
  helper_method :current_business

  # Lookup the account, 404 out if we can't find it
  def ensure_user_exists
    render_404 if !current_account && !current_business
  end
end
