# This parser is almost exactly the same as poetry lock. Maybe some consolidation should occur.

module ManifestAdapters
  module Cargo
    module Parsers
      class Lock < ManifestAdapters::Parsers::Base
        attr_reader :content

        def initialize(content)
          @content = content
        end

        def name; end

        def version; end

        def dependencies
          @dependencies ||= parsed
            .fetch("package", [])
            .filter_map do |dep|
              begin
                create_dependency(dep)
              rescue StandardError => e
                DependencyGraph.logger.info("error getting dependencies from manifest",
                  {
                    "gh.dependency_graph.package_manager" => package_manager,
                    "gh.dependency_graph.manifest.type" => manifest_type,
                  },
                  e
                )
                Failbot.report(e)
                nil
              end
            end
        end

        def malformed?
          dependencies
          !!@malformed
        end

        def package_manager
          "cargo"
        end

        def manifest_type
          "cargo.lock"
        end

        private

        def create_dependency(dependency)
          return unless dependency["source"].present?
          package_name, raw_requirements = dependency["name"], dependency["version"]
          malformed_status = false

          requirements = if valid_requirement?(raw_requirements)
                           "= #{raw_requirements}"
                         else
                           malformed_status = true
                           DependencyGraph.logger.info("invalid requirements",
                                                       "gh.dependency_graph.package_manager" => "cargo",
                                                       "gh.dependency_graph.manifest.type" => "cargo.lock",
                                                       "gh.dependency_graph.manifest.is_malformed" => true,
                                                       "gh.dependency_graph.package.version" => raw_requirements)
                           ""
                        end

          ManifestAdapters::Manifest::Dependency.new(
            package_name: package_name,
            requirements: requirements,
            raw_requirements: raw_requirements,
            scope: "runtime",
            malformed: malformed_status
          )
        end

        def valid_requirement?(requirement)
          return requirement.match?(Versioning::VersionParser::SEMANTIC_PATTERN)
        end

        def parsed
          @parsed ||= Tomlrb.parse(content)
        rescue Tomlrb::ParseError, IndexError => e
          DependencyGraph.logger.info("invalid toml",
            "gh.dependency_graph.package_manager" => package_manager,
            "gh.dependency_graph.manifest.type" => manifest_type,
            "gh.dependency_graph.manifest.is_malformed" => true,
            "exception.type" => e.class.name,
            "exception.message" => e.message
          )
          @malformed = true
          @parsed = {}
        end
      end
    end
  end
end
