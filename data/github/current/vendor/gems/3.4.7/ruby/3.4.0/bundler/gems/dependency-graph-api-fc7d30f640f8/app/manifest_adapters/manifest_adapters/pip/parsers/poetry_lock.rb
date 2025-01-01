module ManifestAdapters
  module Pip
    module Parsers
      class PoetryLock < ::ManifestAdapters::Parsers::Base
        def initialize(content)
          @content = content
        end

        def name; end

        def version; end

        def dependencies
          return @dependencies if @dependencies
          @dependencies = []

          parsed.fetch("package", []).each do |dependency|
            next if dependency.dig("source").present?
            @dependencies << create_dependency(dependency)
          end

          @dependencies
        rescue StandardError => e
          DependencyGraph.logger.info("error parsing manifest",
            {
              "gh.dependency_graph.package_manager" => package_manager,
              "gh.dependency_graph.manifest.type" => "poetry.lock",
            },
            e
          )
          Failbot.report(e)
          @dependencies
        end

        def malformed?
          dependencies
          !!@malformed
        end

        def package_manager
          "pip"
        end

        def manifest_type
          "poetry.lock"
        end

        private

        attr_reader :content

        def valid_requirement?(requirement)
          return requirement.match?(Versioning::VersionParser::SEMANTIC_PATTERN)
        end

        def parsed
          @parsed ||= Tomlrb.parse(content)
        rescue Tomlrb::ParseError, IndexError => e
          DependencyGraph.logger.info(
            "gh.dependency_graph.package_manager" => package_manager,
            "gh.dependency_graph.manifest.type" => "poetry.lock",
            "exception.type" => e.class.name,
            "exception.message" => e.message,
            "gh.dependency_graph.manifest.is_malformed" => true,
          )
          @malformed = true
          @parsed = {}
        end

        def create_dependency(dependency)
          package_name, raw_requirements = dependency["name"], dependency["version"]
          scope = dependency["category"] == "dev" ? "development" : "runtime"
          malformed_status = false

          # Poetry lockfile should be locked to exact versions
          requirements = if valid_requirement?(raw_requirements)
                           "= #{raw_requirements}"
                        else
                          malformed_status = true
                          DependencyGraph.logger.info(
                            "gh.dependency_graph.package_manager" => "pip",
                            "gh.dependency_graph.manifest.type" => "poetry.lock",
                            "gh.dependency_graph.manifest.is_malformed" => true,
                            "gh.dependency_graph.dependency.invalid_requirements" => raw_requirements,
                          )
                          ""
                        end

          ManifestAdapters::Manifest::Dependency.new(
            package_name: package_name,
            requirements: requirements,
            raw_requirements: raw_requirements,
            scope: scope,
            malformed: malformed_status
          )
        end
      end
    end
  end
end
