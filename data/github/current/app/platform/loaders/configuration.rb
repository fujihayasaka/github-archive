# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class Configuration < Platform::Loader
      def self.load(object, method)
        self.for.load([object, method])
      end

      def fetch(object_and_methods)
        with_config_preloaded = Configurable.preload_configuration(
          object_and_methods.map(&:first).uniq
        )

        object_and_methods.each_with_object({}) do |(object, method), values|
          # Find the instance of the record that we preloaded the config entries for
          with_config = with_config_preloaded.find { |instance_with_config| instance_with_config == object }

          values[[object, method]] = with_config&.send(method)
        end
      end
    end
  end
end
