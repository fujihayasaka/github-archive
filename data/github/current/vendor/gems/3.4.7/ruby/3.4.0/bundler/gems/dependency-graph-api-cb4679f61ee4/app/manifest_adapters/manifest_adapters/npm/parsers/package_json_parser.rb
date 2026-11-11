module ManifestAdapters
  module Npm
    module Parsers
      class PackageJsonParser < ManifestAdapters::Parsers::Base
        def initialize(json)
          @json = json
        end

        def package?
          false
        end

        def malformed?
          parsed.blank?
        end

        def is_unity_manifest?
          parsed.key?("unity") ||
          parsed.key?("unityRelease") ||
          dependencies.any? { |d| !d.malformed? && d.package_name.match?(UNITY_PACKAGE_PATTERN) }
        end

        def name
          parsed["name"]
        end

        def version
          parsed["version"]
        end

        def dependencies
          runtime_dependencies + dev_dependencies
        end

        def runtime_dependencies
          Array(parsed["dependencies"]).map do |package_name, requirements|
            dependency(
              package_name: package_name,
              requirements: requirements,
              scope:        Types::Scope[:runtime],
            )
          end
        end

        def dev_dependencies
          Array(parsed["devDependencies"]).map do |package_name, requirements|
            dependency(
              package_name: package_name,
              requirements: requirements,
              scope:        Types::Scope[:development],
            )
          end
        end

        def dependency(package_name:, requirements:, scope:)
          ManifestAdapters::Manifest::Dependency.new(
            package_name: package_name,
            requirements: ManifestAdapters::Npm::Requirements.new(requirements).normalize,
            raw_requirements: requirements,
            scope:        scope,
            malformed:    is_dependency_malformed?(
              package_name: package_name,
              requirements: requirements,
            )
          )
        end

        def parsed
          @parsed ||= begin
            parsed = JSON.parse(json)
            parsed.is_a?(Hash) ? parsed : {}
          rescue JSON::ParserError
            {}
          end
        end

        private

        attr_reader :json

        UNITY_PACKAGE_PATTERN=/^com.unity./i

        def is_dependency_malformed?(package_name:, requirements:)
          ManifestAdapters::Npm::Parsers.is_dependency_malformed(package_name: package_name, requirements: requirements)
        end
      end
    end
  end
end
