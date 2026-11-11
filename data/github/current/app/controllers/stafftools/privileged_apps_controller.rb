# typed: true
# frozen_string_literal: true

module Stafftools
  class PrivilegedAppsController < StafftoolsController

    before_action :dotcom_required

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Ballast,
      ApplicationRecord::Configurations,
      ApplicationRecord::Collab,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Repositories,
      only: [:index]

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Ballast,
      ApplicationRecord::Configurations,
      ApplicationRecord::Collab,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Repositories,
      only: [:show]

    depends_on_clusters ApplicationRecord::Copilot,
      only: [:index, :show],
      optional: true

    def index
      render(
        "stafftools/privileged_apps/index",
        locals: {
          privileged_apps: Apps::Privileged::Registry.all_aliases.sort,
          total_privileged_github_apps: Apps::Privileged::Registry.count_apps(type: "Integration"),
          total_privileged_oauth_apps: Apps::Privileged::Registry.count_apps(type: "OauthApplication")
        }
      )
    end

    def show
      return render_404 if params[:app_alias] == "global" || params[:app_alias] == "first_party"

      return render_404 unless app_config(type: "Integration").present? || app_config(type: "OauthApplication").present?

      app_configs = {}.tap do |cfg|
        %w(Integration OauthApplication).each do |type|
          if app_config(type: type).present?
            cfg[type] = app_config(type: type).merge(
              {
                app: app(type: type),
                app_capabilities: app_capabilities(type: type),
                privileged_capabilities: privileged_capabilities(type: type),
                global_capabilities: global_capabilities(type: type)
              }
            )
          end
        end
      end

      render(
        "stafftools/privileged_apps/show",
        locals: {
          app_configs: app_configs,
          app_alias: params[:app_alias]
        }
      )
    end

    private

    def app_config(type:)
      case type
      when "Integration"
        @integration_config ||= Apps::Privileged::Registry.find_configuration(
          app_alias: params[:app_alias], type: "Integration"
        )
      when "OauthApplication"
        @oauth_application_config ||= Apps::Privileged::Registry.find_configuration(
          app_alias: params[:app_alias], type: "OauthApplication"
        )
      end
    end

    def app(type:)
      case type
      when "Integration"
        @integration ||= Apps::Privileged.integration(params[:app_alias])
      when "OauthApplication"
        @oauth_application ||= Apps::Privileged.oauth_application(params[:app_alias])
      end
    end

    def app_capabilities(type:)
      ivar =
        case type
        when "Integration"; :@integration_app_capabilities
        when "OauthApplication"; :@oauth_application_app_capabilities
        end

      if instance_variable_get(T.must(ivar)).nil?
        instance_variable_set(
          T.must(ivar),
          materialized_capabilities(
            app_config(type: type).fetch(:capabilities),
            app(type: type)
          )
        )
      end

      instance_variable_get(T.must(ivar))
    end

    # Privileged capabilities are overridden by app-specific capabilities
    def privileged_capabilities(type:)
      ivar =
        case type
        when "Integration"; :@integration_privileged_capabilities
        when "OauthApplication"; :@oauth_application_privileged_capabilities
        end

      if instance_variable_get(T.must(ivar)).nil?
        fp_capabilities = Apps::Privileged::Registry.find_configuration(
          app_alias: :first_party,
          type: type
        ).fetch(:capabilities)

        fp_capabilities.delete_if do |key, _|
          app_capabilities(type: type).keys.include?(key)
        end

        instance_variable_set(
          T.must(ivar),
          materialized_capabilities(fp_capabilities, app(type: type))
        )
      end

      instance_variable_get(T.must(ivar))
    end

    # Global capabilities are overridden by both first-party and app-specific
    # capabilities
    def global_capabilities(type:)
      ivar =
        case type
        when "Integration"; :@integration_global_capabilities
        when "OauthApplication"; :@oauth_application_global_capabilities
        end

      if instance_variable_get(T.must(ivar)).nil?
        global_capabilities = Apps::Privileged::Registry.find_configuration(
          app_alias: :global,
          type: type
        ).fetch(:capabilities)

        fp_capabilities = Apps::Privileged::Registry.find_configuration(
          app_alias: :first_party,
          type: type
        ).fetch(:capabilities)

        global_capabilities.delete_if do |key, _|
          fp_capabilities.keys.include?(key) ||
          app_capabilities(type: type).keys.include?(key)
        end

        instance_variable_set(
          T.must(ivar),
          materialized_capabilities(global_capabilities, app(type: type))
        )
      end

      instance_variable_get(T.must(ivar))
    end

    # Capabilities can be simple values or callable. We want values for both so
    # they can be displayed on a page.
    def materialized_capabilities(capabilities, app)
      capabilities.inject({}) do |c, (name, value)|
        c[name] = value.respond_to?(:call) ? value.call(app) : value
        c
      end
    end
  end
end
