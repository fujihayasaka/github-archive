# typed: true
# frozen_string_literal: true

class Settings::DotcomUsersController < ApplicationController
  include Settings::DotcomUsers::ControllerMethods

  before_action :login_required
  before_action :require_dotcom_connection_enabled
  before_action :ensure_dotcom_user_connection_enabled
  before_action :require_connected_instance, only: [:create, :destroy]
  before_action :ensure_unified_connection_enabled, only: [:show]

  stylesheet_bundle :settings
  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1, only: [:show]

  def show
    SecureHeaders.append_content_security_policy_directives(
      request,
      form_action: ["#{GitHub.dotcom_host_protocol}://#{GitHub.dotcom_host_name}"],
      preserve_schemes: GitHub.dotcom_host_protocol != "https",
    )

    render "settings/dotcom_users/show"
  end

  def create
    redirect_to dotcom_user_connection_url

  rescue GitHub::Connect::Authenticator::ConnectionError
    redirect_error
  end

  def destroy
    if dotcom_user.destroy
      redirect_to settings_dotcom_user_path, notice: "Successfully disconnected your #{GitHub.dotcom_host_name_string} account."
    else
      redirect_error
    end
  rescue GitHub::Connect::Authenticator::ConnectionError,
         GitHub::Connect::ApiError
    redirect_error
  end
end
