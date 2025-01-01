# typed: true
# frozen_string_literal: true

module OauthApplicationsHelper
  extend T::Helpers
  extend T::Sig

  abstract!

  # Defined in app/helpers/organizations_helper.rb
  sig { abstract.returns(T.nilable(Organization)) }
  def current_organization; end

  # Also defined in app/helpers/organizations_helper.rb
  sig { abstract.void }
  def org_admins_only; end

  requires_ancestor { ApplicationController } # rubocop:disable GitHub/PreventViewHelpersInControllers

  # App IDs that need to go through the Auth flow with unsupported browsers
  # TODO: Audit this list, remove what we can and move the rest to internal
  # apps with a single capability: :oauth_flow_via_unsupported_browser.
  ALLOWLISTED_APPS = Set.new([
    "e37ffdec11c0245cb2e0", # https://admin.github.com/stafftools/users/Microsoft-corp/applications/681659 (prod: Microsoft Visual Studio)
    "c90d361b80b8a8aedfc6", # https://admin.github.com/stafftools/users/Microsoft-corp/applications/681655 (test: Microsoft Visual Studio)
    "1dc3693fc0e3e8839dee", # https://admin.github.com/stafftools/users/PowerBI/applications/135935 (Microsoft PowerBI)
    "8f58be9bd68d632d1dde", # https://admin.github.com/stafftools/users/TcsMsTeams/applications/1023478 (Microsoft Teams GitHub Bot)
    "053db609fef1aacdcf27", # https://admin.github.com/stafftools/users/Microsoft-Teams/applications/573095 (Microsoft Teams)
    "5a07f09f75c4b12c645d", # https://admin.github.com/stafftools/users/connmgt/applications/249152 (Microsoft Office 365 Connectors)
    "23ef71060e18dbc6f1cd"  # https://admin.github.com/stafftools/users/cloud-management/applications/1037581 (Cloud-management)
  ])

  DISABLED_CLASS = "disabled".freeze

  def token_is_new?(token)
    if new_access = flash[:new_personal_access]
      new_access["id"] == token.id
    end
  end

  def token_is_old_format?(token)
    return false if token.updated_at >= Time.parse("2021-04-01 00:00:00 UTC")
    token.token_last_eight.match? /[a-f0-9]{8}/
  end

  def client_secret_is_new?(client_secret)
    if new_client_secret = flash[:new_client_secret]
      new_client_secret["id"] == client_secret.id
    end
  end

  def oauth_applications_path
    if current_context.is_a? Organization
      settings_org_applications_path(current_context)
    else
      settings_user_applications_path
    end
  end

  def oauth_application_path(app)
    if app.user.organization?
      settings_org_application_path(app.user, app)
    else
      settings_user_application_path(app)
    end
  end

  def oauth_application_revoke_all_tokens_path(app)
    if app.user.organization?
      revoke_all_tokens_settings_org_application_path(app.user, app)
    else
      revoke_all_tokens_settings_user_application_path(app)
    end
  end

  def oauth_application_generate_client_secret_path(app)
    if app.user.organization?
      generate_client_secret_settings_org_application_path(app.user, app)
    else
      generate_client_secret_settings_user_application_path(app)
    end
  end

  def oauth_application_remove_client_secret_path(app, client_secret)
    if app.user.organization?
      remove_client_secret_settings_org_application_path(app.user, app, client_secret)
    else
      remove_client_secret_settings_user_application_path(app, client_secret)
    end
  end

  def new_oauth_application_path
    if current_context.is_a? Organization
      new_settings_org_application_path(current_context)
    else
      new_settings_user_application_path
    end
  end

  def login_required_or_org_admins_only
    if current_context.is_a?(Organization) || params[:organization_id].present?
      current_context = Organization.find_by_login(params[:organization_id])
      org_admins_only
    else
      login_required
    end
  end

  def settings_application_transfer_path(target, xfer_id)
    if target.organization?
      settings_org_application_transfer_path(target, xfer_id)
    else
      settings_user_application_transfer_path(target, xfer_id)
    end
  end

  def settings_oauth_application_advanced_path(app)
    if app.user.organization?
      advanced_settings_org_application_path(app.user, app)
    else
      advanced_settings_user_application_path(app)
    end
  end

  def settings_oauth_application_beta_features_path(app)
    if app.user.organization?
      settings_org_applications_beta_features_path(app.user, app)
    else
      settings_user_applications_beta_features_path(app)
    end
  end

  def current_context
    current_organization || current_user
  end

  def can_transfer_application?(app)
    return false if app.pending_transfer?
    return true unless current_context.organization?
    current_organization&.adminable_by?(current_user)
  end

  def link_to_new_oauth_app(name)
    classes = new_oauth_app_button_classes(
      current_context, %w[btn btn-sm]
    )

    ActionController::Base.helpers.link_to(name, new_oauth_application_path, :class => classes, "data-pjax" => true)
  end

  def new_oauth_app_button_classes(context, classes)
    if context.reached_applications_creation_limit?(application_type: OauthApplication)
      classes << DISABLED_CLASS
    end

    classes.join(" ")
  end

  # Apps that need to go through the Auth flow with unsupported browsers
  def disable_oauth_authorize_button?(app)
    !Apps::Internal.capable?(:oauth_flow_via_unsupported_browser, app: app) &&
      !ALLOWLISTED_APPS.include?(request.params[:client_id])
  end
end
