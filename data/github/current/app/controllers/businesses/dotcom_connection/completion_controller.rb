# typed: true
# frozen_string_literal: true

class Businesses::DotcomConnection::CompletionController < Businesses::BusinessController
  include Businesses::DotcomConnection::ControllerMethods

  before_action :business_owner_required
  before_action :require_dotcom_connection_enabled

  depends_on_clusters ApplicationRecord::Mysql1, only: [:show]

  def show
    if dotcom_connection.temp_authentication_token && state_matches_session?
      ActiveRecord::Base.connected_to(role: :writing) do
        # The token is always refreshed before sending a request to GitHub.com
        # (see GitHub::Connect.github_app_authenticated) so it doesn't really matter the token we store when
        # connecting for the first time.
        # This makes it possible to receive the redirect after Connecting to GitHub.com without sending the
        # token as part of the URL.
        dotcom_connection.create "needs-refresh", params[:app_id], params[:installation_id], params[:client_secret]
        dotcom_connection.update_application_info
      end
      redirect_to admin_settings_dotcom_connection_enterprise_path(GitHub.global_business), notice: "Successfully connected your Enterprise instance to #{GitHub.dotcom_host_name_string}."
    else
      redirect_error
    end
  rescue GitHub::Connect::Authenticator::AuthenticationError => error
    redirect_error error
  end
end
