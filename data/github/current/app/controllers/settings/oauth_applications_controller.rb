# typed: true
# frozen_string_literal: true

class Settings::OauthApplicationsController < ApplicationController
  include Settings::ControllerMethods

  depends_on_clusters ApplicationRecord::Mysql1,
                      ApplicationRecord::Mysql5,
                      ApplicationRecord::Collab,
                      ApplicationRecord::Mysql2,
                      ApplicationRecord::NotificationsEntries,
                      ApplicationRecord::IamAbilities,
                      ApplicationRecord::Lodge

  depends_on_clusters ApplicationRecord::Copilot, optional: true

  before_action :login_required

  javascript_bundle :settings
  stylesheet_bundle :settings

  def index
    @pending_transfers = current_user.inbound_application_transfers
    @applications = current_user.oauth_applications.limit(15).page(params[:page])

    render "oauth_applications/developer"
  end

  private

  def set_context_title
    context_region_preset :developer_settings
  end
end
