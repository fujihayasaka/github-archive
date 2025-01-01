require "yarnlock"

module ManifestAdapters
  module Npm
    module Parsers
      class YarnLockParserV2 < ManifestAdapters::Parsers::Base
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

        def dependency(package_name:, requirements:, raw_requirements:, scope:)
          ManifestAdapters::Manifest::Dependency.new(
            package_name: package_name,
            requirements: ManifestAdapters::Npm::Requirements.new(requirements).normalize,
            raw_requirements: raw_requirements,
            scope:        scope,
            malformed:    is_dependency_malformed?(
              package_name: package_name,
              requirements: requirements,
            )
          )
        end

        def dependencies
          dependencies = parsed.map do |_, package_blob|
            package_id = package_blob["resolution"]

            # package_id can look like '@actions/core@npm:^1.2.6', so we need to split on the last @
            package_name, _, requirements_string_with_optional_source = package_id.rpartition "@"

            # "Handle" the case where optional source is present
            if requirements_string_with_optional_source.include? ":"
              # If we have an annotation of package source, only use NPM.
              source, requirements_string = requirements_string_with_optional_source.split ":"
              # I don't 100% understand this annotation but it is present in files. If something
              # is *not* an npm package, we shouldn't report it, but it's also not an error case.
              next if source.downcase != "npm"
            end

            # We don't end up using the raw requirements string. This might seem unintuitive,
            # but that string only represents the "not-locked" source for the version. Since
            # we have a real version, that user requested string is not super meaningful to us.
            dependency(
              package_name: package_name,
              requirements: ManifestAdapters::Npm::Requirements.new(package_blob["version"]).normalize,
              raw_requirements: package_blob["version"],
              scope:        Types::Scope[:runtime],
            )
          end.compact

          dependencies.uniq
        end

        def parsed
          @parsed ||= begin
            manifest = YAML.safe_load content
            manifest.delete "__metadata"
            manifest
          rescue Psych::SyntaxError => e
            DependencyGraph.logger.info(
              "gh.dependency_graph.package_manager" => "npm",
              "gh.dependency_graph.manifest.type" => "yarn.lock",
              "exception.message" => e.message,
              "exception.type" => e.class.name,
              "gh.dependency_graph.manifest.is_malformed" => true,
              "gh.dependency_graph.manifest.parser" => "YarnLockParserV2"
            )
            []
          end
        end

        private

        attr_accessor :content

        def is_dependency_malformed?(package_name:, requirements:)
          ManifestAdapters::Npm::Parsers.is_dependency_malformed(package_name: package_name, requirements: requirements)
        end
      end
    end
  end
end
