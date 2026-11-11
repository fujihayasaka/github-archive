# typed: strict
# frozen_string_literal: true

class Settings::CredentialsController < ApplicationController
  include Settings::ControllerMethods

  before_action :login_required
  before_action :not_ghes_required
  before_action :feature_flag_required
  before_action :emu_required_for_deletion, only: [:destroy]

  stylesheet_bundle :settings
  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Permissions,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  sig { void }
  def show
    render "settings/credentials/show"
  end

  sig { void }
  def destroy
    if params[:verify].blank?
      flash[:error] = "Confirmation text is required."
      return redirect_to settings_credentials_path
    end

    unless verify_confirmation
      flash[:error] = "Confirmation text does not match."
      return redirect_to settings_credentials_path
    end

    unless business
      flash[:error] = "You must select a valid enterprise."
      return redirect_to settings_credentials_path
    end

    case revocation_type
    when :authorizations_only
      enqueue_revocation_job(enterprise_id: T.must(business).id, revoke_emu_credentials: false)
      flash[:notice] = "Currently revoking authorizations for keys and tokens owned or authorized " \
        "by your account. You can view all affected credentials in your security log."
    when :credentials_and_authorizations
      enqueue_revocation_job(enterprise_id: T.must(business).id, revoke_emu_credentials: true)
      flash[:notice] = "Currently deleting all keys and tokens owned or authorized by your account. " \
        "You can view all affected credentials in your security log."
    else
      flash[:error] = "Unknown revocation type."
    end

    redirect_to settings_credentials_path
  end

  private

  sig { returns(T::Boolean) }
  def verify_confirmation
    expected = "#{current_user.display_login} credentials"
    params[:verify].present? && params[:verify].to_s.casecmp?(expected)
  end

  sig { returns(T.nilable(Symbol)) }
  def revocation_type
    case params[:revocation_type]
    when "authorizations" then :authorizations_only
    when "credentials_and_authorizations" then :credentials_and_authorizations
    end
  end

  sig { returns(T.nilable(Business)) }
  memoize def business
    if current_user.is_enterprise_managed?
      current_user.enterprise_managed_business
    else
      id = params[:enterprise_id]
      return nil unless id.present? && id.to_i > 0
      current_user.businesses.find_by(id: id.to_i)
    end
  end

  sig { params(enterprise_id: Integer, revoke_emu_credentials: T::Boolean).void }
  def enqueue_revocation_job(enterprise_id:, revoke_emu_credentials:)
    RevokeUserCredentialAuthorizationsJob.perform_later(
      current_user.id,
      current_user.id,
      enterprise_id,
      revoke_emu_credentials: revoke_emu_credentials,
    )
    GitHub.logger.info(
      "Settings::CredentialsController#destroy",
      revoke_emu_credentials: revoke_emu_credentials,
      user_id: current_user.id,
      user_login: current_user.display_login,
    )
  end

  sig { void }
  def emu_required_for_deletion
    render_404 if revocation_type == :credentials_and_authorizations && !current_user.is_enterprise_managed?
  end

  sig { void }
  def feature_flag_required
    render_404 unless FeatureFlag.vexi.enabled?(:credential_self_revocation_single_user, current_user, default: false)
  end

  sig { void }
  def not_ghes_required
    render_404 if GitHub.enterprise?
  end
end
