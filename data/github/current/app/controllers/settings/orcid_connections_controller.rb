# typed: strict
# frozen_string_literal: true

class Settings::OrcidConnectionsController < ApplicationController
  include Settings::ControllerMethods
  include ProfilesHelper

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    only: [:new, :show]

  before_action :require_enablement
  before_action :login_required
  before_action :require_code, only: :show
  before_action :require_valid_state, only: :show

  sig { void }
  def new
    state = SecureRandom.hex
    session[:orcid_oauth_state] = state

    redirect_to orcid_client.oauth_url(redirect_uri: settings_orcid_connection_url, state:)
  end

  sig { void }
  def show
    result = orcid_client.get_authenticated_identifier(code: params[:code])
    result.on(
      success: lambda do |successful_result|
        GitHub.logger.info("orcid-oauth-get-authenticated-identifier", **successful_result.log_attrs)

        orcid_record = current_user.build_orcid_record(identifier: successful_result.identifier)
        if orcid_record.valid?
          select_write_database { orcid_record.save }

          flash[:notice] = "Successfully connected your GitHub account with ORCID."
        else
          flash[:error] = "Unable to connect your GitHub account with ORCID: " \
            "#{orcid_record.errors.full_messages.to_sentence}."
        end
      end,
      failure: lambda do |failed_result|
        GitHub.logger.warn("orcid-oauth-get-authenticated-identifier", **failed_result.log_attrs)

        flash[:error] = "Unable to connect your GitHub account with ORCID: #{failed_result.user_message}."
      end
    )

    redirect_to settings_user_profile_url
  end

  sig { void }
  def destroy
    current_user.orcid_record&.destroy!
    flash[:notice] = "Successfully disconnected ORCID from your GitHub Account."

    redirect_to settings_user_profile_url
  end

  private

  sig { void }
  def require_enablement
    render_404 unless show_orcid_controls?
  end

  sig { void }
  def require_valid_state
    session_state = session.delete(:orcid_oauth_state)

    unless params[:state].present? && session_state.present? && params[:state] == session_state
      flash[:error] = "Unable to connect your GitHub account with ORCID."
      redirect_to settings_user_profile_url
    end
  end

  sig { void }
  def require_code
    unless params[:code].present?
      flash[:error] = "Unable to connect your GitHub account with ORCID."
      redirect_to settings_user_profile_url
    end
  end

  sig { returns(OrcidClient) }
  memoize def orcid_client
    OrcidClient.new
  end
end
