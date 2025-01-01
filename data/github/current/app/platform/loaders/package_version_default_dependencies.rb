# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class PackageVersionDefaultDependencies < Platform::Loader
      def self.load(version_id)
        self.for.load(version_id)
      end

      def fetch(version_ids)
        results = ::Registry::Dependency.where(registry_package_version_id: version_ids, dependency_type: :default)

        dependencies_by_version_id = {}
        version_ids.each do |version_id|
          dependencies_by_version_id[version_id] = []
        end

        results.each do |dep|
          dependencies_by_version_id[dep.registry_package_version_id] << dep
        end

        dependencies_by_version_id
      end
    end
  end
end
