# typed: true
# frozen_string_literal: true

class EnterpriseInstallationsController < ApplicationController
  include EnterpriseInstallationsHelper

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:complete]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:upgrade]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:new]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:complete, :new, :upgrade], optional: true

  CODEPATH_ENTERPRISE_INSTALLATION = "controller/enterprise_installations".freeze

  skip_before_action :perform_conditional_access_checks, only: %w(new) # rubocop:disable GitHub/DoNotSkipCapBeforeAction
  before_action :dotcom_required
  before_action :login_required
  before_action :installation_owner_admin_required, except: %w(new)
  before_action :require_valid_installation_token, only: %w(new)
  before_action :require_valid_state, only: %w(new complete upgrade upgrade_confirm)
  before_action :require_valid_hostname_in_data, only: %w(new)
  before_action :require_owner_integration_installation, only: %w(complete upgrade upgrade_confirm)

  def new
    SecureHeaders.append_content_security_policy_directives(request, {
      form_action: ["#{protocol(installations_data["http_only"])}://#{installations_data["host_name"]}"],
      preserve_schemes: protocol(installations_data["http_only"]) != "https",
    })

    businesses = current_user.businesses(membership_type: :admin).order("businesses.name ASC")
    owned_organizations = current_user.owned_organizations
    enterprise_owned_orgs = Organization.none
    owned_organizations = owned_organizations
      .joins("LEFT OUTER JOIN business_organization_memberships ON business_organization_memberships.organization_id = users.id")
      .where("business_organization_memberships.id IS NULL")

    enterprise_owned_orgs = current_user.owned_organizations
      .joins("LEFT OUTER JOIN business_organization_memberships ON business_organization_memberships.organization_id = users.id")
      .where("business_organization_memberships.id IS NOT NULL")

    render "enterprise_installations/new", locals: {
      businesses: businesses,
      owned_organizations: owned_organizations,
      enterprise_owned_orgs: enterprise_owned_orgs,
    }
  end

  def complete # rubocop:todo GitHub/UseRestfulActions
    ActiveRecord::Base.connected_to(role: :writing) do
      token = current_integration_installation.generate_token(code_path: CODEPATH_ENTERPRISE_INSTALLATION)
      GitHub.kv.del("ghe-install-token-#{token_hash}") # rubocop:todo GitHub/DoNotUseGlobalKv
    end

    # this is a hardcoded url because cloud doesn't know the enterprise account
    # slug on the server instance to formulate a full enterprise route.
    # this route will redirect to the global enterprise account on the server
    redirect_to "#{protocol(installation.http_only)}://#{installation.host_name}/admin/dotcom_connection/complete/?app_id=#{installation.github_app.id}&installation_id=#{current_integration_installation.id}&state=#{params[:state]}&client_secret=#{params[:client_secret]}"
  end

  def destroy
    DestroyEnterpriseInstallationJob.perform_later(installation)

    # Let other pages redirect back when needed (for example, the billing
    # settings page which lists installations too).
    # If the owner still has other installations, it's worth showing them;
    # otherwise, we'd rather go up one level (to its profile).
    if params[:redirect_to_path].present?
      safe_redirect_to params[:redirect_to_path]
    elsif installation.owner.enterprise_installations.many?
      redirect_to installation_owner_installations_path
    else
      redirect_to installation_owner_profile_path
    end
  end

  def upgrade # rubocop:todo GitHub/UseRestfulActions
    SecureHeaders.append_content_security_policy_directives(request, { form_action: ["#{protocol(installation.http_only)}://#{installation.host_name}"], preserve_schemes: installation.http_only })

    integration_diff = installation.github_app_latest_version_diff

    if integration_diff.permissions_changed?
      features_added_descriptions, features_removed_descriptions = github_app_diff_messages(integration_diff)
      render "enterprise_installations/upgrade", locals: {
        state: params[:state],
        redirect_to: params[:redirect_to],
        features_added_descriptions: features_added_descriptions,
        features_removed_descriptions: features_removed_descriptions,
        # Any features that are added or removed that don't require a permissions change will
        # need to be rendered as hidden fields to keep track for instrumentation
        features_added: params[:features_added],
        features_removed: params[:features_removed]
      }
    else
      # We still want to instrument the change with our params[:features_added] and params[:features_removed] details, but then just return to GHES
      installation.instrument_features_updated(params[:features_added], params[:features_removed], current_user)
      return_to = upgrade_return_base_url
      return_to.query_values = { state: params[:state] }
      redirect_to return_to.to_s
    end
  end

  def upgrade_confirm # rubocop:todo GitHub/UseRestfulActions
    SecureHeaders.append_content_security_policy_directives(request, { form_action: ["#{protocol(installation.http_only)}://#{installation.host_name}"], preserve_schemes: installation.http_only })

    result = ActiveRecord::Base.connected_to(role: :writing) do
      EnterpriseInstallation::FeatureUpdater.perform(
        installation, actor: current_user,
        non_perm_change_features: { added: params[:features_added], removed: params[:features_removed] },
        entry_point: :enterprise_installations_controller_upgrade_confirm,
      )
    end

    return_to = upgrade_return_base_url

    query = {}
    query[:state] = params[:state] if result.success?
    query[:error] = result.error if result.error
    return_to.query_values = query

    redirect_to return_to.to_s
  end

  private

  def upgrade_return_base_url
    # URI composition is for legacy cases where a `return_to` parameter isn't supplied
    installation_server_return_to || Addressable::URI.new(
      scheme: protocol(installation.http_only),
      host: installation.host_name,
      path: "/admin/dotcom_connection/change_complete")
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless installation # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    installation.owner
  end

  def installation_owner_admin_required
    return if installation.owner.adminable_by?(current_user)

    return_to = installation_server_return_to
    return render_404 unless return_to

    return_to.query_values = { error: "User is not an admin on the connected cloud account" }
    redirect_to return_to.to_s
  end

  # An installation should always exist when this is called, however it might not in the case
  # of running `complete` on a new GitHub Connect connection because of a replication lag.
  # We use the primary to get around this lag and allow the connection process to complete.
  memoize def installation
    ActiveRecord::Base.connected_to(role: :writing, prevent_writes: true) do
      EnterpriseInstallation.find(params[:id])
    end
  end
  # for EnterpriseInstallationsHelper consumption:
  alias_method :current_installation, :installation

  def installation_owner_installations_path
    if installation.owner.is_a?(Organization)
      organization_enterprise_installations_list_path(installation.owner)
    else
      enterprise_enterprise_installations_path(installation.owner)
    end
  end

  def installation_owner_profile_path
    if installation.owner.is_a?(Organization)
      settings_org_profile_path(installation.owner)
    else
      settings_profile_enterprise_path(installation.owner)
    end
  end

  def require_owner_integration_installation
    return if current_integration_installation

    return_to = installation_server_return_to
    return render_404 unless return_to

    return_to.query_values = { error: "An error was found with your cloud connection.  Please reconnect your server to your cloud account." }
    redirect_to return_to.to_s
  end
end
