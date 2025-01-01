# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    module Registry
      class PackageMetadata < Platform::Loader

        def self.load(package_version_id, metadata_key)
          self.for(metadata_key).load(package_version_id)
        end

        def initialize(name)
          @name = name
        end

        private

        attr_reader :viewer

        def fetch(package_version_ids)
          scope = ::Registry::Metadatum.scoped

          if @name.present?
            scope = scope.where(name: @name)
          end

          scope = scope.where(package_version_id: package_version_ids)

          scope.group_by(&:package_version_id).tap do |results|
            results.default_proc = -> (_, _) { [] }
          end
        end
      end
    end
  end
end
