# typed: true
# frozen_string_literal: true

class Settings::IntegrationsController < ApplicationController
  include IntegrationsControllerMethods
  include IntegrationManagerHelper

  # Even though the receive_manifest action is a POST, it is idempotent and merely presents
  # the user with a view without making any changes to the database. Since the client side POST
  # is initiated from a host that is not GitHub, CSRF checks need to be disabled.
  skip_before_action :verify_authenticity_token, only: [:receive_manifest]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Lodge,
    only: [:new]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    ApplicationRecord::Lodge,
    only: [:authorizations]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Lodge,
    only: [:advanced]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Lodge,
    only: [:beta_features]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    ApplicationRecord::Lodge,
    only: [:new_from_manifest]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Lodge,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Lodge,
    only: [:installations]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    only: [:keys]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Lodge,
    only: [:permissions]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    ApplicationRecord::Lodge,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    ApplicationRecord::Lodge,
    only: [:copilot]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:beta_features, :index, :installations, :new, :permissions, :show, :new_from_manifest, :advanced, :authorizations, :copilot],
    optional: true

  # In order to make the manifests flow work on instances that run with private mode enabled,
  # we have to disable the guard for this action so that we get the chance to register
  # the manifests payload in the KV and cookies.
  if GitHub.enterprise?
    skip_before_action :enforce_private_mode, only: [:receive_manifest], if: -> { GitHub.private_mode_enabled? }
  end

  before_action :require_app_manifest_token_cookie, only: [:new_from_manifest]

  javascript_bundle :settings
  stylesheet_bundle :settings

  def authorizations # rubocop:todo GitHub/UseRestfulActions
    order = if params[:o] == "used-desc"
      "oauth_authorizations.accessed_at desc"
    elsif params[:o] == "used-asc"
      "oauth_authorizations.accessed_at asc"
    else
      "integrations.name asc"
    end

    @authorizations = current_user.oauth_authorizations.github_apps
      .joins(:integration)
      .includes(:integration)
      .order(order)
      .limit(15)
      .page(params[:page])

    view = create_view_model(
      Integrations::AuthorizationsView,
      authorizations: @authorizations,
    )
    render "integrations/authorizations", locals: { view: view }
  end

  def new_from_manifest # rubocop:todo GitHub/UseRestfulActions
    owner_from_new_manifest

    unless @manifest_kv_data
      return manifest_not_found!(msg: "Unable to load App Manifest, please try again.")
    end

    if requested_owner_mismatch?
      set_requested_owner_mismatch_flash_message
    end

    manifest = IntegrationManifest.new(
      data: @manifest_kv_data["manifest"],
      owner: @requested_owner,
    )

    view = create_view_model(
      Integrations::NewFromManifestView,
      manifest: manifest,
      owner: @requested_owner,
      manifest_token: @manifest_kv_id,
      state: @manifest_kv_data["state"],
    )

    if manifest.valid?
      render "integrations/settings/new_from_manifest", locals: { view: view }
    else
      render "integrations/settings/invalid_manifest", locals: { view: view }
    end
  end

  def create_manifest # rubocop:todo GitHub/UseRestfulActions
    state = params[:integration_manifest].delete(:state)

    owner_from_create_manifest

    if requested_owner_mismatch?
      set_requested_owner_mismatch_flash_message
    end

    manifest = IntegrationManifest.new(
      owner: @requested_owner,
      creator: current_user,
      name: params[:integration_manifest][:name],
      data: params[:integration_manifest][:data],
    )

    if !requested_owner_mismatch? && manifest.save
      redirect_uri = Addressable::URI.parse(manifest.data["redirect_url"])
      query_values = redirect_uri.query_values || {}
      query_values[:code] = manifest.code
      query_values[:state] = state if state.present?

      redirect_uri.query_values = query_values

      render "integrations/settings/manifest_redirect",
        locals: { redirect_url: redirect_uri.to_s },
        layout: "layouts/redirect"
    else
      opts = { manifest: manifest, owner: @requested_owner }
      opts[:state] = state if state.present?
      view = create_view_model(Integrations::NewFromManifestView, opts)
      render "integrations/settings/new_from_manifest", locals: { view: view }
    end
  end

  private

  # receive_manifest always results in a redirect to /login so it is safe to
  # skip the private mode check
  def enforce_multi_tenant_private_mode?
    return false if action_name == "receive_manifest"

    super
  end

  def tenant_verification_enforceable
    logged_in? ? :yes : :no
  end

  def emu_visibility_enforceable
    logged_in? ? :yes : :no
  end

  def emu_ownership_enforceable
    logged_in? ? :yes : :no
  end

  def ip_allowlist_enforceable
    logged_in? ? super : :no
  end

  def external_conditional_access_policy_enforceable
    logged_in? ? super : :no
  end

  def require_active_external_identity_session?
    logged_in? ? super : false
  end

  def two_factor_enforceable
    logged_in? ? :yes : :no
  end

  def target_for_conditional_access
    if create_integration_manifest_on_create?
      owner_from_create_manifest
    elsif action_name == "new_from_manifest"
      owner_from_new_manifest
    elsif logged_in?
      current_user
    else
      :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    end
  end

  def owner_from_manifest(requested_owner_login)
    if (org = Organization.find_by(login: requested_owner_login))
      if org.adminable_by?(current_user) || manages_all_integrations?(user: current_user, owner: org)
        return org
      end
    end

    current_user
  end

  def owner_from_create_manifest
    return @requested_owner if defined?(@requested_owner)

    @requested_owner_login = params[:integration_manifest].delete(:owner_login)

    ActiveRecord::Base.connected_to(role: :writing) do
      Apps::KV.store.del(params[:integration_manifest].delete(:manifest_token))
    end

    @requested_owner = owner_from_manifest(@requested_owner_login)
  end

  def owner_from_new_manifest
    return @requested_owner if defined?(@requested_owner)

    unless (@manifest_kv_id = cookies[:app_manifest_token])
      return current_user
    end

    # Due to replication delay we might not be successful reading from replicas
    # as this read happens very soon after our write
    @manifest_kv_data = ActiveRecord::Base.connected_to(role: :writing, prevent_writes: true) do
      Apps::KV.store.get(@manifest_kv_id).value { nil }
    end

    unless @manifest_kv_data
      return current_user
    end

    @manifest_kv_data = JSON.parse(@manifest_kv_data)
    @requested_owner_login = @manifest_kv_data["owner"]

    @requested_owner = owner_from_manifest(@requested_owner_login)
  end

  def require_app_manifest_token_cookie
    return if cookies[:app_manifest_token]

    manifest_not_found!
  end

  def manifest_not_found!(msg: "We didn't find an App Manifest for your request.")
    flash[:error] = msg
    redirect_to new_settings_user_app_path
  end

  def current_context
    current_user
  end

  def requested_owner_mismatch?
    return false if @requested_owner_login == "current_user"

    !@requested_owner_login.casecmp?(@requested_owner.display_login)
  end

  def set_requested_owner_mismatch_flash_message
    flash[:notice] = "You don't have permission to create apps for #{@requested_owner_login}. Please confirm you have appropriate permissions for this account and have entered the name correctly. You may still create this app for your own account."
  end
end
