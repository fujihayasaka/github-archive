# typed: true
# frozen_string_literal: true

# Query for internal Apps of different types, with particular capabilities
module Apps
  class Privileged
    class Query
      def initialize
        @oauth_application_by_capablity = {}
        @integration_by_capability = {}
      end

      # Public: all apps of a given type that have been granted a capability.
      #
      # capability  - Symbol. The capability that all matching internal Apps
      #               should have.
      # type        - Class. One of `Integration` or `OauthApplication`. The
      #               type of app to return.
      #
      # Returns: An array of Integration or OauthApplication models.
      def with_capability(capability, type:)
        get_or_set(capability, type: type) do
          all_configured_apps_of_type(type).select do |app|
            Apps::Privileged.capable?(capability, app: app)
          end
        end
      end

      # Public: all apps of a given type that do not have a capability. The
      # inverse of `#with_capability`.
      #
      # capability  - Symbol. The capability that all matching internal Apps
      #               should not have.
      # type        - Class. One of `Integration` or `OauthApplication`. The
      #               type of app to return.
      #
      # Returns: An array of Integration or OauthApplication models.
      def without_capability(capability, type:)
        all_configured_apps_of_type(type) - with_capability(capability, type: type)
      end

      private

      def get_or_set(capability, type:)
        cached_capabilities = cache_for_type(type)
        if capabilities_for_type = cached_capabilities[type]
          capabilities_for_type
        else
          result = yield
          cached_capabilities[type] = result
          result
        end
      end

      def cache_for_type(type)
        case type.name
        when "Integration" then @integration_by_capability
        when "OauthApplication" then @oauth_application_by_capablity
        else
          {}
        end
      end

      def all_configured_apps_of_type(type)
        case type.name
        when "Integration"
          @all_configured_integrations ||= type.default_scoped.
            where(id: Apps::Privileged::Registry.all_configured_ids_of_type("Integration"))
        when "OauthApplication"
          @all_configured_oauth_apps ||= type.default_scoped.
            where(id: Apps::Privileged::Registry.all_configured_ids_of_type("OauthApplication"))
        else
          []
        end
      end
    end
  end
end
