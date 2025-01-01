module ManifestAdapters
  module Pip
    module Parsers
      class Pipfile < ManifestAdapters::Parsers::Base
        def initialize(content)
          @content = content
        end

        def name; end

        def version; end

        def dependencies
          @dependencies ||= runtime_dependencies + development_dependencies
        rescue Pip::DependencyString::ParseError
          @malformed = true
          @dependencies = []
        end

        def malformed?
          dependencies
          !!@malformed
        end

        private

        attr_reader :content

        def runtime_dependencies
          dependencies_from_section("packages", scope: Types::Scope[:runtime])
        end

        def development_dependencies
          dependencies_from_section("dev-packages", scope: Types::Scope[:development])
        end

        def dependencies_from_section(section, scope:)
          parsed.fetch(section, {}).map do |package_name, version|
            requirements = version if version.is_a?(String)

            if version.is_a?(Hash)
              # File and path dependencies use a checksum in lieu of a package
              # name.
              next if version["file"] || version["path"]
              requirements = version["version"]
            end

            raw_requirements = requirements
            requirements = Pip::DependencyString.parse_requirement_set(requirements)

            ManifestAdapters::Manifest::Dependency.new(
              package_name: package_name,
              raw_requirements: raw_requirements,
              requirements: requirements.to_s,
              scope: scope
            )
          end.compact
        end

        def parsed
          @parsed ||= Tomlrb.parse(content)
        rescue Tomlrb::ParseError, IndexError
          @malformed = true
          @parsed = {}
        end
      end
    end
  end
end
