module ManifestAdapters
  module Pip
    module Parsers
      class PipfileLock < ManifestAdapters::Parsers::Base
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
          dependencies_from_section("default", scope: Types::Scope[:runtime])
        end

        def development_dependencies
          dependencies_from_section("develop", scope: Types::Scope[:development])
        end

        def dependencies_from_section(section, scope:)
          parsed.fetch(section, {}).map do |package_name, attributes|
            next unless attributes.is_a?(Hash)

            # File and path dependencies use a checksum in lieu of a package
            # name.
            next if attributes.has_key?("file") || attributes.has_key?("path")

            requirements = Pip::DependencyString.parse_requirement_set(attributes["version"])

            ManifestAdapters::Manifest::Dependency.new(
              package_name: package_name,
              requirements: requirements.to_s,
              raw_requirements: attributes["version"].to_s,
              scope: scope
            )
          end.compact
        end

        def parsed
          @parsed ||= JSON.parse(content)
        rescue JSON::ParserError
          @malformed = true
          @parsed = {}
        end
      end
    end
  end
end
