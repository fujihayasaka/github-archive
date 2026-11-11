# typed: strict
# frozen_string_literal: true

class Stafftools::Users::CredentialsController < StafftoolsController
  include Stafftools::Users::ControllerLayoutMethods

  before_action :ensure_user_exists
  before_action :not_ghes_required
  before_action :feature_flag_required
  before_action :emu_required_for_deletion, only: [:destroy]

  layout :security_layout

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
    render "stafftools/users/credentials/show"
  end

  sig { void }
  def destroy
    unless verify_confirmation
      flash[:error] = "Username does not match."
      return redirect_to stafftools_user_credentials_path(this_user)
    end

    resolved_business = business
    unless resolved_business
      flash[:error] = "You must select a valid enterprise."
      return redirect_to stafftools_user_credentials_path(this_user)
    end

    case revocation_type
    when :authorizations_only
      enqueue_revocation_job(enterprise_id: resolved_business.id, revoke_emu_credentials: false)
      flash[:notice] = "Currently revoking SSO authorizations for #{this_user.display_login}."
    when :credentials_and_authorizations
      enqueue_revocation_job(enterprise_id: resolved_business.id, revoke_emu_credentials: true)
      flash[:notice] = "Currently deleting all keys and tokens for #{this_user.display_login}."
    else
      flash[:error] = "Unknown revocation type."
    end

    redirect_to stafftools_user_credentials_path(this_user)
  end

  private

  sig { returns(T::Boolean) }
  def verify_confirmation
    params[:verify].present? && params[:verify].to_s.casecmp?("#{this_user.display_login} credentials")
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
    if this_user.is_enterprise_managed?
      this_user.enterprise_managed_business
    else
      id = params[:enterprise_id]
      return nil unless id.present? && id.to_i > 0
      this_user.businesses.find_by(id: id.to_i)
    end
  end

  sig { params(enterprise_id: Integer, revoke_emu_credentials: T::Boolean).void }
  def enqueue_revocation_job(enterprise_id:, revoke_emu_credentials:)
    RevokeUserCredentialAuthorizationsJob.perform_later(
      current_user.id,
      this_user.id,
      enterprise_id,
      revoke_emu_credentials: revoke_emu_credentials,
    )
    GitHub.logger.info(
      "Stafftools::Users::CredentialsController#destroy",
      revoke_emu_credentials: revoke_emu_credentials,
      actor_id: current_user.id,
      actor_login: current_user.display_login,
      target_user_id: this_user.id,
      target_user_login: this_user.display_login,
    )
  end

  sig { void }
  def emu_required_for_deletion
    render_404 if revocation_type == :credentials_and_authorizations && !this_user.is_enterprise_managed?
  end

  sig { void }
  def feature_flag_required
    render_404 unless FeatureFlag.vexi.enabled?(:credential_revocation_single_user, current_user, default: false)
  end

  sig { void }
  def not_ghes_required
    render_404 if GitHub.enterprise?
  end
end
