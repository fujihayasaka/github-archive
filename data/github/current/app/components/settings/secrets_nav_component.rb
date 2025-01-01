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
      Secrets::AppsHelper.multi_integrations_enabled_for_user?(@user)
    end

    memoize def enabled_apps
      enabled_app_names = Secrets::AppsHelper.enabled_app_names(@user)
      enabled_app_names.delete(Secrets::AppsHelper::PRIVATE_REGISTRY_APP_NAME) if !@entity.is_a?(::Organization)
      return enabled_app_names if !@entity.is_a?(::Organization) || @is_admin
      return [ACTIONS_APP_NAME] if (@fgps[:organization_actions_secrets] || @fgps[:organization_actions_variables]) && enabled_app_names.include?(ACTIONS_APP_NAME)
    end

    def secrets_path(app_name)
      case @entity
      when ::Repository
        repository_secrets_path(user_id: @entity.owner, repository: @entity, app_name: app_name)
      when ::Organization
        if app_name == Secrets::AppsHelper::ACTIONS_APP_NAME && @fgps[:organization_actions_variables] && !@fgps[:organization_actions_secrets] && !@is_admin
          organization_variables_path(@entity, app_name: app_name)
        else
          settings_org_secrets_path(@entity, app_name: app_name)
        end
      end
    end

    def display_name(app_name)
      Secrets::AppsHelper.display_name_for(app_name)
    end

    def highlight(app_name)
      Secrets::AppsHelper.highlight_for(app_name, @user)
    end

    def section_title
      "Secrets and variables"
    end
  end
end
