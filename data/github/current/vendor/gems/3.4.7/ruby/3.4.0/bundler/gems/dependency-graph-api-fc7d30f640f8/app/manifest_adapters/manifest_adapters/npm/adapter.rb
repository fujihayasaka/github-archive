module ManifestAdapters
  module Npm
    class Adapter < ManifestAdapters::Adapter
      def self.manifest_type(filename:, path:)
        case filename.to_s.strip.downcase
        when "package.json"      then Types::Manifest[:package_json]
        when "package-lock.json" then Types::Manifest[:package_lock_json]
        when "yarn.lock"         then Types::Manifest[:yarn_lock]
        when "pnpm-lock.yaml"    then Types::Manifest[:pnpm_lock]
        end
      end

      def self.package_manager
        Types::PackageManager[:npm]
      end

      private

      def parsed
        @parsed ||= case manifest_type
        when Types::Manifest[:package_json]
          parser = ManifestAdapters::Npm::Parsers.package_json(content)
          # Fix for https://github.com/github/dependency-graph/issues/1361
          raise UnityManifestError if parser.is_unity_manifest?
          parser
        when Types::Manifest[:package_lock_json]
          ManifestAdapters::Npm::Parsers.package_json_lock(content)
        when Types::Manifest[:yarn_lock]
          ManifestAdapters::Npm::Parsers.yarn_lock(content)
        when Types::Manifest[:pnpm_lock]
          ManifestAdapters::Npm::Parsers.pnpm_lock(content)
        end
      end
    end

    class UnityManifestError < StandardError; end
  end
end
