require "yarnlock"

module ManifestAdapters
  module Npm
    module Parsers
      class YarnLockParser < ManifestAdapters::Parsers::Base
        def initialize(content)
          @content = content
        end

        def malformed?
          parsed.blank?
        end

        # yarn.lock doesn't expose the name of the project, so return nil.
        def name
          nil
        end

        # yarn.lock doesn't expose the version of the project, so return nil.
        def version
          nil
        end

        def dependency(package_name:, requirements:, scope:)
          ManifestAdapters::Manifest::Dependency.new(
            package_name: package_name,
            requirements: ManifestAdapters::Npm::Requirements.new(requirements).normalize,
            raw_requirements: requirements.to_s,
            scope:        scope,
            malformed:    is_dependency_malformed?(
              package_name: package_name,
              requirements: requirements,
            )
          )
        end

        def dependencies
          dependencies = parsed.map do |package|
            dependency(
              package_name: package.package,
              requirements: package.version,
              scope:        Types::Scope[:runtime],
            )
          end

          dependencies.uniq
        end

        def parsed
          @parsed ||= begin
            Yarnlock.parse content
          rescue TypeError, RuntimeError, NoMethodError, ArgumentError, JSON::ParserError => e
            DependencyGraph.logger.info("error parsing manifest",
              {
                "gh.dependency_graph.package_manager" => "npm",
                "gh.dependency_graph.manifest.type" => "yarn.lock",
              },
              e
            )

            # Return an empty array if yarn.lock parser failed
            []
          end
        end

        private

        attr_accessor :content

        def is_dependency_malformed?(package_name:, requirements:)
          # if requirements is any Semantic Version, its a valid package reference
          return true unless requirements.is_a? Semantic::Version

          ManifestAdapters::Npm::Parsers.is_dependency_malformed(package_name: package_name, requirements: requirements.to_s)
        end
      end
    end
  end
end
