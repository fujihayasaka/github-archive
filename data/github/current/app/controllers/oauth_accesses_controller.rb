# typed: true
# frozen_string_literal: true

class OauthAccessesController < ApplicationController

  # The following actions do not require conditional access checks:
  # - show: redirects to another oauth endpoint and does not access
  #   protected organization resources before redirecting.
  skip_before_action :perform_conditional_access_checks, only: "show" # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  before_action :login_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:show]

  def show
    redirect_to settings_oauth_authorization_path(find_access.application.key)
  end

  private

  def find_access
    OauthAccessTokens.domain.user_access_by_id(current_user.id, params[:id].to_i, strict: true)
  end
end
