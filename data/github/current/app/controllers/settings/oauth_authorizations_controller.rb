# typed: true
# frozen_string_literal: true

class Settings::OauthAuthorizationsController < ApplicationController
  include Settings::ControllerMethods

  depends_on_clusters ApplicationRecord::Mysql1,
                      ApplicationRecord::Billing,
                      ApplicationRecord::IamAbilities,
                      ApplicationRecord::Collab,
                      ApplicationRecord::Mysql2,
                      ApplicationRecord::NotificationsEntries,
                      ApplicationRecord::Mysql5

  depends_on_clusters ApplicationRecord::Copilot, optional: true

  before_action :login_required

  javascript_bundle :settings
  stylesheet_bundle :settings

  def index
    order = if params[:o] == "used-desc"
      "oauth_authorizations.accessed_at desc"
    elsif params[:o] == "used-asc"
      "oauth_authorizations.accessed_at asc"
    else
      "oauth_applications.name asc"
    end

    @authorizations = current_user.oauth_authorizations.user_revocable(OauthApplication)
      .references(:oauth_application)
      .includes(:oauth_application)
      .preload(:public_keys)
      .order(order)
      .limit(15).page(params[:page])

    render "oauth_applications/user"
  end

  private

  def set_context_title
    context_region_preset :developer_settings
  end
end
