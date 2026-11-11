# typed: true
# frozen_string_literal: true

class Settings::DotcomUsers::CallbackController < ApplicationController
  include Settings::DotcomUsers::ControllerMethods

  before_action :login_required
  before_action :require_dotcom_connection_enabled
  before_action :ensure_dotcom_user_connection_enabled
  before_action :require_connected_instance

  depends_on_clusters ApplicationRecord::Mysql1, only: [:show]

  def show
    if state_matches_session?
      token = github_connect_authenticator.request_oauth_token(params[:code], oauth_info, dotcom_connection.client_secret)
      dotcom_user.token = token
      dotcom_user.login = user_login(token)
      ActiveRecord::Base.connected_to(role: :writing) do
        dotcom_user.save
      end
      redirect_to settings_dotcom_user_path, notice: "Successfully connected with your #{GitHub.dotcom_host_name_string} account."
    else
      redirect_error
    end
  rescue GitHub::Connect::Authenticator::ConnectionError
    redirect_error
  end
end
