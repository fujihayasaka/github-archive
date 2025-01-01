module ManifestAdapters
  module Pub
    module Parsers
      class Yaml < ManifestAdapters::Parsers::Base

        def initialize(content)
          @content = content
        end

        def name
          @parsed.dig("name")
        end

        def version
          @parsed.dig("version")
        end

        def dependencies
          return @dependencies if defined?(@dependencies)

          @dependencies, overriden_dependencies = {}, {}

          collected_dependencies, overriden = extract_scoped_dependencies(parsed)

          # Override any dependencies in the dependency_overrides section
          # https://dart.dev/tools/pub/dependencies#dependency-overrides
          overriden_dependencies = overriden.reduce Hash.new, :merge unless overriden.empty?

          collected_dependencies.except(:dependency_overrides).each do |key, entry|
            scope = entry[:scope]
            entry[:deps].each do |name, data|
              # We do not treat SDK dependencies as dependencies, this is consistent with dependabot.
              # Additionally, we do not treat git dependencies as there is no highly confident way to get a version.
              next if %w[sdk git].include?(data)
              dependency = parse_dependency(scope, name, data, overriden_dependencies[name])
              @dependencies[dependency.package_name] = dependency
            end
          end

          @dependencies = @dependencies.values
          @dependencies
        rescue StandardError => e
          DependencyGraph.logger.info("error parsing manifest",
            {
              "gh.dependency_graph.package_manager" => "pub",
              "gh.dependency_graph.manifest.type" => "pubspec.yaml",
            },
            e
          )
          Failbot.report(e)
          @dependencies = @dependencies.values
        end

        def malformed?
          dependencies
          !!@malformed
        end

        private

        attr_reader :content

        def extract_scoped_dependencies(current_table)
          collected, overriden = {}, []

          current_table.each do |key, value|
            next unless value.is_a?(Hash)
            case key.to_s
            when "dev_dependencies"
              collected[:dev_dependencies] = { scope: Types::Scope[:development], deps: value }
            when "dependencies"
              collected[:dependencies] = { scope: Types::Scope[:runtime], deps: value }
            when "dependency_overrides"
              overriden << value
            else
              next
            end
          end
          return collected, overriden
        end

        # we need scope and other data particular to the parent dependency group type
        # so we build ManifestAdapters::Manifest::Dependency records directly
        def parse_dependency(scope, dep_name, data, override_data = nil)
          data_to_parse = override_data.nil? ? data : override_data

          raw_requirements, malformed_version_spec = extract_requirements(data_to_parse)
          requirements, malformed_requirements = Requirements.parse(raw_requirements)

          malformed_status = dep_name.blank? | malformed_version_spec | malformed_requirements
          DependencyGraph.logger.info(
            "gh.dependency_graph.package_manager" => "pub",
            "gh.dependency_graph.manifest.type" => "pubspec.yaml",
            "exception.message" => "invalid or unhandled dependency record",
            "gh.dependency_graph.manifest.is_malformed" => true,
            "gh.dependency_graph.dependency.invalid_record" => "#{dep_name} => #{data}"
          ) if malformed_status

          ManifestAdapters::Manifest::Dependency.new(
            package_name: dep_name,
            requirements: requirements,
            raw_requirements: raw_requirements,
            scope: scope,
            malformed: malformed_status
          )
        end

        # A Pub dependency entry will be expressed as either:
        # 1. a simple version String with three numbers separated by dots e.g. "2.0.0"
        # 2. a simple version String with three numbers separated by dots followed by build or pre-release data e.g. "2.0.0-alpha"
        # Dependencies that are of type hosted have a hash with a "version" key https://dart.dev/tools/pub/dependencies#hosted-packages
        def extract_requirements(data)
          case data
          when String
            return data, false
          when Hash
            if data.include?("version")
              return data["version"], false
            else
              return "", true
            end
          else
            return "", true
          end
        end

        def parsed
          return @parsed if @parsed
          manifest = YAML.safe_load(@content)
          if !manifest.is_a?(Hash)
            @malformed = true
            @parsed = {}
            return @parsed
          end

          @parsed = manifest
        rescue Psych::SyntaxError, Psych::BadAlias => e
          DependencyGraph.logger.info("parse error",
            "gh.dependency_graph.package_manager" => "pub",
            "gh.dependency_graph.manifest.type" => "pubspec.spec",
            "exception.message" => e.message,
            "exception.type" => e.class.name,
          )
          @malformed = true
          @parsed = {}
        rescue StandardError => e
          DependencyGraph.logger.info("error parsing manifest",
            {
              "gh.dependency_graph.package_manager" => "pub",
              "gh.dependency_graph.manifest.type" => "pubspec.spec",
            },
            e
          )
          @malformed = true
          # Very curious what errors will pop up here so sending parsing errors to Sentry to start (as an experiment)
          # Normally we would just log and leave it
          Failbot.report!(e)
          @parsed = {}
        end
      end
    end
  end
end
