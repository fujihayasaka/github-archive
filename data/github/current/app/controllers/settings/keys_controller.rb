# typed: true
# frozen_string_literal: true

class Settings::KeysController < ApplicationController
  include Settings::ControllerMethods
  include OrganizationsHelper
  include Organization::CredentialAuthorizationsHelper

  before_action :login_required
  before_action :ensure_trade_restrictions_allows_org_settings_access
  before_action :apply_selected_link

  stylesheet_bundle :settings
  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show, :index], optional: true

  helper_method :show_sso_ready_badge?

  def index
    render "settings/keys/index", locals: { view: view, public_key: public_key }
  end

  def show
    render "settings/keys/index", locals: { view: view, public_key: public_key }
  end

  private

  def view
    create_view_model(Settings::SshKeysView, ssh_keys: user_ssh_keys, git_signing_ssh_public_keys: user_git_signing_ssh_public_keys)
  end

  def public_key
    current_user.public_keys.find_by(id: params[:id])
  end

  def user_ssh_keys
    current_user.public_keys.to_a
  end

  def user_git_signing_ssh_public_keys
    current_user.git_signing_ssh_public_keys.to_a
  end

  def apply_selected_link
    @selected_link = :ssh_and_gpg_keys
  end
end
