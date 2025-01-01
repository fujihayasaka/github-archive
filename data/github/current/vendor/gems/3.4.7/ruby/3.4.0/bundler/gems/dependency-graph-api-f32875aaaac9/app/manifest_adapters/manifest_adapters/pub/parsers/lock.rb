module ManifestAdapters
  module Pub
    module Parsers
      class Lock < ManifestAdapters::Parsers::Base

        def initialize(content)
          @content = content
        end

        def name; end

        def version; end

        def dependencies
          return @dependencies if @dependencies
          @dependencies = []

          manifest = parsed
          manifest.each do |package_name, dependency|
            parsed_dependency = parse_dependency(package_name, dependency)
            @dependencies << parse_dependency(package_name, dependency) unless parsed_dependency.nil?
          end

          @dependencies
        rescue StandardError => e
          DependencyGraph.logger.info("error parsing manifest",
            {
              "gh.dependency_graph.package_manager" => "pub",
              "gh.dependency_graph.manifest.type" => "pubspec.lock",
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

        private

        attr_reader :content

        def parse_dependency(package_name, dependency)
          return if dependency.nil? || package_name.nil?
          return unless %w[hosted git].include?(dependency["source"]) # Only support hosted and git dependencies we can locate

          malformed_status = false
          raw_version = dependency["version"]
          raw_name = dependency["description"]["name"]
          requirements = parse_version(raw_version) # TODO: Add as a class method to base adapter
          parsed_scope = parse_scope(dependency["dependency"])
          malformed_status = raw_version.blank? || raw_name.blank? || parsed_scope.nil?

          ManifestAdapters::Manifest::Dependency.new(
            package_name: package_name,
            requirements: requirements,
            raw_requirements: raw_version,
            scope: parsed_scope,  # Lockfile does scope transitive dependencies
            malformed: malformed_status
          )
        end

        def parse_scope(scope)
          case scope
          when "transitive"
            Types::Scope[:runtime]
          when "direct main"
            Types::Scope[:runtime]
          when "direct overridden"
            Types::Scope[:runtime]
          when "direct dev"
            Types::Scope[:development]
          else
            DependencyGraph.logger.info(
              "gh.dependency_graph.package_manager" => "pub",
              "gh.dependency_graph.manifest.type" => "pubspec.lock",
              "gh.dependency_graph.manifest.is_malformed" => true,
              "exception.message" => "unknown dependency scope",
              "gh.dependency_graph.dependency.scope" => scope
            )
            Types::Scope[:runtime]
          end
        end

        def parse_version(raw_version)
          possible_semver = raw_version.match(Versioning::VersionParser::SEMANTIC_PATTERN)
          possible_semver ? "= #{possible_semver.string}" : nil
        end

        def parsed
          return @parsed if @parsed
          manifest = YAML.safe_load(@content)
          if !manifest.is_a?(Hash)
            @malformed = true
            return []
          end

          parsed_dependencies = {}

          packages = manifest["packages"]
          if !packages.is_a?(Hash)
            @malformed = true
            return []
          end

          packages.each do |name, package|
            next if !package.is_a?(Hash)
            parsed_dependencies[name] = package if !name.nil?
          end

          @parsed = parsed_dependencies
        rescue Psych::SyntaxError, Psych::BadAlias => e
          DependencyGraph.logger.info(
            "gh.dependency_graph.package_manager" => "pub",
            "gh.dependency_graph.manifest.type" => "pubspec.lock",
            "gh.dependency_graph.manifest.is_malformed" => true,
            "exception.type" => e.class.name,
            "exception.message" => e.message,
          )
          @malformed = true
          @parsed = []
        rescue StandardError => e
          DependencyGraph.logger.info("error parsing manifest",
            {
              "gh.dependency_graph.package_manager" => "pub",
              "gh.dependency_graph.manifest.type" => "pubspec.lock",
              "gh.dependency_graph.manifest.is_malformed" => true,
            },
            e
          )
          @malformed = true
          # Very curious what errors will pop up here so sending parsing errors to Sentry to start (as an experiment)
          # Normally we would just log and leave it
          Failbot.report!(e)
          @parsed = []
        end
      end
    end
  end
end
