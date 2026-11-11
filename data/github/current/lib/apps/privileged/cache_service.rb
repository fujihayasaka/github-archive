# typed: true
# frozen_string_literal: true

module Apps
  class Privileged
    class CacheService
      include Singleton

      def self.get_property(name:, app_id:, app_type:)
        instance.get_property(name:, app_id:, app_type:)
      end

      def self.set_property(name:, app_id:, app_type:, value:)
        instance.set_property(name:, app_id:, app_type:, value:)
      end

      # Internal. Reset the properties memoization for an app.
      #
      # Not available in the production environment.
      def self.unset_cached_properties!(app_id:, app_type:)
        instance.unset_cached_properties!(app_id:, app_type:)
      end

      def get_property(name:, app_id:, app_type:)
        # Ensure our memoized singleton instance variable is defined before use.
        @properties_by_app_and_prop_name = {} unless defined?(@properties_by_app_and_prop_name)

        @properties_by_app_and_prop_name["#{app_type}:#{app_id}:#{name}"]
      end

      def set_property(name:, app_id:, app_type:, value:)
        # Ensure our memoized singleton instance variable is defined before use.
        @properties_by_app_and_prop_name = {} unless defined?(@properties_by_app_and_prop_name)

        @properties_by_app_and_prop_name["#{app_type}:#{app_id}:#{name}"] = value
        value
      end

      # Internal. Reset the properties memoization for an app.
      #
      # Not available in the production environment.
      def unset_cached_properties!(app_id:, app_type:)
        return unless Apps::Privileged::Registry.registry_configurable?
        return unless defined?(@properties_by_app_and_prop_name)

        @properties_by_app_and_prop_name.delete_if do |key, _|
          /\A#{app_type}:#{app_id}:/.match(key)
        end
      end
    end
  end
end
