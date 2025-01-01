# typed: true
# frozen_string_literal: true
module Settings
  class EnterpriseInstallationsController < ApplicationController
    include OrganizationsHelper
    include BusinessesHelper
    include EnterpriseInstallationsHelper

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Configurations,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Billing,
      ApplicationRecord::Collab,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Repositories,
      ApplicationRecord::Copilot,
      only: [:index]

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Collab,
      only: [:new]

    class UnknownControllerActionExternalIdentyOrganization < StandardError; end

    before_action :dotcom_required
    before_action :login_required
    before_action :ensure_current_organization_admin, except: %w(new create)
    before_action :require_valid_installation_token, only: %w(new create)
    before_action :require_valid_state, only: %w(new create)
    before_action :require_valid_hostname_in_data, only: %w(new create)
    before_action :require_valid_server_id_in_data, only: %w(create)

    javascript_bundle :settings

    # List enterprise installations mapped to this organization
    def index
      render "settings/enterprise_installations/index", locals: {
        org_enterprise_installations: org_enterprise_installations,
        stats_export_url: settings_enterprise_installation_stats_export_url(current_organization)
      }
    end

    # this method is used by GHES versions < 2.17. it can be removed after all customers are on GHES >= 2.17
    def new
      redirect_to new_enterprise_installation_url(state: params[:state], token: params[:token])
    end

    def create
      return render_404 if !target_organization

      if conflict_message
        flash[:error] = conflict_message
        return redirect_to new_enterprise_installation_path(token: params[:token], state: params[:state])
      end

      result = EnterpriseInstallation::Creator.perform(target_organization,
        actor: current_user,
        server_data: installations_data,
        entry_point: :settings_enterprise_installations_controller_create
      )

      if result.success?
        set_github_app_icon(result.enterprise_installation, current_user)
        redirect_to complete_enterprise_installation_url(result.enterprise_installation, token: params[:token], state: params[:state], client_secret: result.client_secret)
      else
        flash[:error] = "Failed to connect #{installations_data["host_name"]} to the #{target_organization.name} organization."
        redirect_to new_enterprise_installation_path(token: params[:token], state: params[:state])
      end
    end

    def stats_export # rubocop:todo GitHub/UseRestfulActions
      # Download the usage metrics from the S4 service
      export_data = current_organization.s4_usage_metrics(format: params[:format])
      current_organization.instrument_connect_usage_metrics_export actor: current_user, total_entries: export_data[:record_count]
      send_data export_data[:blob], type: export_data[:content_type], filename: "stats-export.#{params[:format]}"
    end

    def destroy
      enterprise_installation = org_enterprise_installations.find(params["id"])
      DestroyEnterpriseInstallationJob.perform_later(enterprise_installation)

      if org_enterprise_installations.many?
        redirect_to organization_enterprise_installations_list_path(params["organization_id"])
      else
        redirect_to settings_org_profile_path(current_organization)
      end
    end

    private

    memoize def conflict_message
      if EnterpriseInstallation.where(server_id: installations_data["server_id"]).exists?
        "A connection with the server ID #{installations_data["server_id"]} already exists. Please disconnect the existing instance and try again."
      elsif conflicting_installations(target_organization, installations_data["host_name"]).exists?
        "A connection with the host name #{installations_data["host_name"]} already exists. Please disconnect the existing instance and try again."
      end
    end

    def ensure_current_organization_admin
      render_404 if !current_organization.present? || !org_admin?
    end

    def current_installation # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
      @current_installation ||= begin
        # rubocop:todo GitHub/DoNotUseGlobalKv
        EnterpriseInstallation.find_by(id: GitHub.kv.get("ghe-install-id-#{token_hash}").value { nil })
        # rubocop:enable GitHub/DoNotUseGlobalKv
      end
    end

    def target_for_conditional_access
      case params[:action]
      when "index", "destroy", "stats_export"
        # current_organization can be nil if the current_user doesn't have access to it
        # in this case, we can ignore conditional access policies and subject them to regular authz checks
        return :no_target_for_conditional_access unless current_organization # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
        current_organization
      when "create"
        # target_organization can be nil if the current_user doesn't have admin access to it
        # in this case, we can ignore conditional access policies and subject them to regular authz checks
        return :no_target_for_conditional_access unless target_organization # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
        target_organization
      when "new"
        # Lets you see the page listing each org you're an admin on without a specific SAML session yet
        :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      else
        # Whenever a new route is added to this controller it needs to be accounted for in this method
        raise UnknownControllerActionExternalIdentyOrganization
      end
    end

    def target_organization # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
      @organization ||= target_organizations.where(login: params[:login]).first
    end

    def target_organizations
      orgs_with_admin_access
    end

    def orgs_with_admin_access
      current_user.owned_organizations
    end

    memoize def org_enterprise_installations
      current_organization.enterprise_installations
    end
  end
end
