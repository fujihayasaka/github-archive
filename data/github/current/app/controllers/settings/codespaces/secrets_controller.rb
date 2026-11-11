# typed: true
# frozen_string_literal: true

class Settings::Codespaces::SecretsController < ApplicationController
  include ApplicationController::VerifiedFetchDependency
  allow_verified_fetch only: [:destroy]

  before_action :login_required
  before_action :require_codespaces_feature

  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    only: [:edit]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    only: [:new]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:edit, :new],
    optional: true

  def new
    public_key = public_key(current_user)
    secret = Codespaces::UserSecret.new(key_id: public_key[0])
    render "settings/codespaces/secrets/new", locals: { public_key:, secret: }
  end

  def create
    secret = Codespaces::UserSecret.new(secret_params.merge(encrypted_value: params[:encrypted_value]).to_h)
    if secret.save
      flash[:notice] = "Secret added."
      redirect_to settings_user_codespaces_path
    else
      errors = secret.errors.present? ? secret.errors.full_messages.join(", ") : "Please try again."
      flash[:error] = "Failed to add secret. #{errors}"
      redirect_to settings_user_codespaces_path
    end
  end

  def edit
    public_key = public_key(current_user)
    secret = Codespaces::UserSecret.new(
      name: params[:name],
      user: current_user,
      key_id: public_key[0]
    )
    if secret.fetch_credential
      # Make sure we can find the credential in Credz first...
      visible_repositories = cap_filter.authorized_resources(secret.repositories)
      render "settings/codespaces/secrets/edit", locals: {
        public_key: public_key,
        secret: secret,
        visible_repositories: visible_repositories
      }
    else
      render_404
    end
  end

  def update
    secret = Codespaces::UserSecret.new(secret_params.merge(name: params[:name], encrypted_value: params[:encrypted_value]).to_h)
    if secret.update
      flash[:notice] = "Secret updated."
      redirect_to settings_user_codespaces_path
    else
      errors = secret.errors.present? ? secret.errors.full_messages.join(", ") : "Please try again."
      flash[:error] = "Failed to update secret. #{errors}"
      redirect_to settings_user_codespaces_path
    end
  end

  def destroy
    secret = Codespaces::UserSecret.new(secret_params.merge(name: params[:name]))
    if secret.delete
      flash[:notice] = "Secret deleted."
      redirect_to settings_user_codespaces_path
    else
      errors = secret.errors.present? ? secret.errors.full_messages.join(", ") : "Please try again."
      flash[:error] = "Failed to delete secret. #{errors}"
      redirect_to settings_user_codespaces_path
    end
  end

  private def target_for_conditional_access
    # If we aren't logged in we cannot simply return nil here because the CAP
    # checks will blow up. We have to explicitly return this special symbol
    # instead so they don't try to do things with nil.
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess

    current_user
  end

  private

  def secret_params
    params.require(:codespaces_user_secret).
      permit(:key_id, :name, :encrypted_value, repository_ids: []).
      merge(user: current_user)
  end

  def public_key(user)
    Secrets.github_public_key(owner: user, key_name: Platform::EncryptionKeys::CODESPACES_SECRETS)
  end

  def codespaces_integration
    ::Apps::Privileged.integration(:codespaces_production)
  end

  def require_codespaces_feature
    render_404 unless current_user&.codespaces_feature_enabled?
  end
end
