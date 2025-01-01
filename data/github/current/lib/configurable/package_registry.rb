# typed: false
# frozen_string_literal: true

module Configurable
  module PackageRegistry
    def enable_package_registry(actor)
      config.enable(KEY, actor)
    end

    def disable_package_registry(actor)
      config.disable(KEY, actor)
    end

    def package_registry_config_enabled?
      config.enabled?(Configurable::PackageRegistry::KEY)
    end

    KEY = "github-package-registry".freeze
  end
end
