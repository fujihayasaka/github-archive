# typed: true
# frozen_string_literal: true

module Settings
  class SecretsNavComponent < ApplicationComponent
    delegate_missing_to :@item

    include Secrets::AppsHelper

    def initialize(user:, entity:, is_admin: false, fine_grained_permissions: {}, **system_arguments)
      @user = user
      @entity = entity
      @system_arguments = system_arguments

      # Dummy item to make the component work with the wrapping nav list. Hopefully this can go away
      # when another integration is added and we stop relying on #show_multi_integration_nav?
      @item = T.unsafe(Primer::Beta::NavList::Item).new(label: "Secrets", **@system_arguments)
      @fgps = fine_grained_permissions
      @is_admin = is_admin
    end

    # only needed until an integration besides actions is rolled out. This is to prevent spoiling the surprise for users
    def show_multi_integration_nav?
      Secrets::AppsHelper.multi_integrations_enabled_for_user?(@user, entity: @entity)
    end

    memoize def enabled_apps
      org = if @entity.is_a?(::Organization)
        @entity
      elsif @entity.is_a?(::Repository) && @entity.owner.is_a?(::Organization)
        @entity.owner
      end
      enabled_app_names = Secrets::AppsHelper.enabled_app_names(@user, org:)
      enabled_app_names.delete(Secrets::AppsHelper::PRIVATE_REGISTRY_APP_NAME) unless @entity.is_a?(::Organization)
      enabled_app_names.delete(Secrets::AppsHelper::ELM_EXPORTER_APP_NAME) unless @entity.is_a?(::Organization)
      return enabled_app_names if @is_admin

      visible = []
      if (@fgps[:actions_secrets] || @fgps[:actions_variables]) && enabled_app_names.include?(ACTIONS_APP_NAME)
        visible << ACTIONS_APP_NAME
      end
      if agent_fgp_custom_role_enabled? && (@fgps[:agent_secrets] || @fgps[:agent_variables]) && enabled_app_names.include?(AGENTS_APP_NAME)
        visible << AGENTS_APP_NAME
      end
      visible
    end

    def agent_fgp_custom_role_enabled?
      flag_target = @entity.is_a?(::Repository) ? @entity.owner : @entity
      FeatureFlag.vexi.enabled?(:agents_secrets_fgp_custom_role, flag_target, default: false)
    end

    def secrets_path(app_name)
      case @entity
      when ::Repository
        if variables_only_path?(app_name)
          repository_variables_path(user_id: @entity.owner, repository: @entity, app_name: app_name)
        else
          repository_secrets_path(user_id: @entity.owner, repository: @entity, app_name: app_name)
        end
      when ::Organization
        if variables_only_path?(app_name)
          organization_variables_path(@entity, app_name: app_name)
        elsif app_name == Secrets::AppsHelper::ELM_EXPORTER_APP_NAME
          settings_org_elm_exporter_secrets_path(@entity)
        else
          settings_org_secrets_path(@entity, app_name: app_name)
        end
      end
    end

    # Returns true when the non-admin user has the variables FGP but not the
    # secrets FGP for the given app, so the nav item should link to the
    # variables path instead of the secrets path.
    def variables_only_path?(app_name)
      return false if @is_admin
      case app_name
      when Secrets::AppsHelper::ACTIONS_APP_NAME
        @fgps[:actions_variables] && !@fgps[:actions_secrets]
      when Secrets::AppsHelper::AGENTS_APP_NAME
        agent_fgp_custom_role_enabled? && @fgps[:agent_variables] && !@fgps[:agent_secrets]
      else
        false
      end
    end

    def display_name(app_name)
      Secrets::AppsHelper.display_name_for(app_name)
    end

    def highlight(app_name)
      Secrets::AppsHelper.highlight_for(app_name, @user, entity: @entity)
    end

    def section_title
      "Secrets and variables"
    end
  end
end
