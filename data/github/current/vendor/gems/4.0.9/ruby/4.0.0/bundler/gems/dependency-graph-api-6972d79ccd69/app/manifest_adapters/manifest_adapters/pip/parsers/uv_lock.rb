module ManifestAdapters
  module Pip
    module Parsers
      class UvLock < ::ManifestAdapters::Parsers::Base
        def initialize(content)
          @content = content
        end

        def name; end

        def version; end

        def dependencies
          return @dependencies if @dependencies
          @dependencies = []

          parsed.fetch("package", []).each do |package|
            source = package.dig("source")
            next if source.present? && !registry_source?(source)

            @dependencies << create_dependency(package)
          end

          @dependencies
        rescue StandardError => e
          DependencyGraph.logger.info("error parsing manifest",
            {
              "gh.dependency_graph.package_manager" => package_manager,
              "gh.dependency_graph.manifest.type" => "uv.lock",
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
          "uv.lock"
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
            "gh.dependency_graph.manifest.type" => "uv.lock",
            "exception.type" => e.class.name,
            "exception.message" => e.message,
            "gh.dependency_graph.manifest.is_malformed" => true,
          )
          @malformed = true
          @parsed = {}
        end

        def registry_source?(source)
          source.key?("registry")
        end

        def dev_package_names
          @dev_package_names ||= begin
            dev_names = Set.new
            dependency_groups = parsed.dig("dependency-groups") || {}
            dev_group = dependency_groups["dev"] || []
            dev_group.each do |dep|
              if dep.is_a?(Hash)
                dev_names << dep["name"]
              elsif dep.is_a?(String)
                dev_names << dep
              end
            end
            dev_names
          end
        end

        def create_dependency(package)
          package_name = package["name"]
          raw_requirements = package["version"]
          scope = dev_package_names.include?(package_name) ? "development" : "runtime"
          malformed_status = false

          # uv lockfile should be locked to exact versions
          requirements = if raw_requirements.present? && valid_requirement?(raw_requirements)
                           "= #{raw_requirements}"
                        else
                          malformed_status = true
                          DependencyGraph.logger.info(
                            "gh.dependency_graph.package_manager" => "pip",
                            "gh.dependency_graph.manifest.type" => "uv.lock",
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
