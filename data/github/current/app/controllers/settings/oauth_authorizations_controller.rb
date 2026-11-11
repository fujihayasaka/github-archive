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
                      ApplicationRecord::Mysql5,
                      ApplicationRecord::Lodge

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
    # Avoid cross-cluster JOINs between oauth_authorizations and oauth_applications.
    # Instead of using includes/references (which produces a LEFT JOIN), we:
    # 1. Explicitly scope to OauthApplication-type authorizations via .oauth_apps
    # 2. Use preload(:application) to eager-load via a separate query (no JOIN)
    # 3. For name-based sorting, resolve the order in a separate query against
    #    oauth_applications, then use FIELD() to apply that order without a JOIN.
    scope = current_user.oauth_authorizations.oauth_apps.user_revocable(OauthApplication)

    if order == "oauth_applications.name asc"
      app_ids = scope.distinct.pluck(:application_id)
      sorted_app_ids = app_ids.any? ? OauthApplication.where(id: app_ids).order(name: :asc).pluck(:id) : []

      if sorted_app_ids.any?
        order = Arel.sql("FIELD(oauth_authorizations.application_id, #{sorted_app_ids.join(",")})")
      else
        order = "oauth_authorizations.application_id asc"
      end
    end

    @authorizations = scope
      .preload(:application, :public_keys)
      .order(order)
      .limit(15).page(params[:page])

    render "oauth_applications/user"
  end

  private

  def set_context_title
    context_region_preset :developer_settings
  end
end
