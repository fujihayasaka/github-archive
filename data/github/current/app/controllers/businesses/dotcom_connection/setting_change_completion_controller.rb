# typed: true
# frozen_string_literal: true

class Businesses::DotcomConnection::SettingChangeCompletionController < Businesses::BusinessController
  include Businesses::DotcomConnection::ControllerMethods

  before_action :business_owner_required
  before_action :require_dotcom_connection_enabled

  depends_on_clusters ApplicationRecord::Mysql1, only: [:show]

  def show
    if state_matches_session?
      ActiveRecord::Base.connected_to(role: :writing) do
        apply_pending_config_changes
      end
      redirect_to admin_settings_dotcom_connection_enterprise_path(GitHub.global_business)
    else
      ActiveRecord::Base.connected_to(role: :writing) do
        dotcom_connection.clear_pending_features
      end
      flash[:notice] = nil
      flash[:error] = params[:error]
      error = GitHub::Connect::ApiError.new(params[:error]) if params[:error]
      redirect_error(error)
    end
  end
end
