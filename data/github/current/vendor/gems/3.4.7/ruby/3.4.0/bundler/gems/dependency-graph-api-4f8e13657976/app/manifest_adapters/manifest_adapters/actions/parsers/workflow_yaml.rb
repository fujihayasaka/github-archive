module ManifestAdapters
  module Actions
    module Parsers
      class WorkflowYaml < ManifestAdapters::Parsers::Base

        def initialize(content, private_repository:)
          @content = content
          @private_repository = private_repository
        end

        def name; end

        def version; end

        def dependencies
          return @dependencies if @dependencies

          @dependencies = []

          manifest = parsed

          manifest.each do |dependency|
            @dependencies << create_dependency(dependency)
          end

          @dependencies
        rescue StandardError => e
          DependencyGraph.logger.info("error parsing manifest",
            {
              "gh.dependency_graph.package_manager" => "actions",
              "gh.dependency_graph.manifest.type" => "workflow.yaml",
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

        def create_dependency(dependency)
          return if dependency.nil?

          malformed_status = false
          name, raw_version = dependency.split("@")
          malformed_status = name.blank? || raw_version.blank?
          requirements = parse_version(raw_version)

          #NOTE: just uploading branch/sha requirements as is now will be rejected by SemVer models
          # Need to figure out our workaround for Actions - Punt to PMA work

          ManifestAdapters::Manifest::Dependency.new(
            package_name: name,
            requirements: requirements,
            raw_requirements: raw_version,
            scope: "runtime",
            malformed: malformed_status
          )
        end

        def parse_version(raw_version)
          return "" if raw_version.nil?

          resolve_actions_semver(raw_version) || "= #{raw_version}"
        end

        def resolve_actions_semver(raw_version)
           # after some experimenting and review of DG Actions versions in the data warehouse
           # I determined that continuing to rely on Versioning::VersionParser::SEMANTIC_PATTERN
           # is too risky if we're going to classify "named versions" vs. "Actions convention semvers"
          elems = raw_version.match(/\A\s*v(?<major>\d+)(?<minor>\.(\d+|[*Xx]))?(?<patch>\.(\d+|[*Xx]))?(?<rest>[-+].*)?\z/)
          return nil unless elems

          major = elems[:major]     # always present in this case, but may be corrupted!
          minor = elems[:minor] ? elems[:minor].gsub(/^\./, "") : "*"  # strip . prefix, wildcard if nil
          patch = elems[:patch] ? elems[:patch].gsub(/^\./, "") : "*"  # strip . prefix, wildcard if nil
          rest = elems[:rest] || "" # empty string if nil; if corrupt semver elems land here, good luck

          "= #{major}.#{minor}.#{patch}#{rest}"
        end

        def parsed
          return @parsed if @parsed
          manifest = YAML.safe_load(@content, permitted_classes: [Date, Time, Symbol], aliases: true)
          if !manifest.is_a?(Hash)
            @malformed = true
            return []
          end

          parsed_dependencies = []

          jobs = manifest["jobs"]
          return [] if !jobs.is_a?(Hash)

          jobs.each do |name, job|
            next if !job.is_a?(Hash)
            job_dep = job["uses"]
            parsed_dependencies << job_dep if job_dep.is_a?(String)

            steps = job["steps"]
            next unless steps.is_a?(Array)

            steps.each do |step|
              next if !step.is_a?(Hash)
              step_dep = step["uses"]
              parsed_dependencies << step_dep if step_dep.is_a?(String)
            end
          end

          # reject docker image dependencies
          valid_dependencies = parsed_dependencies.compact.reject { |dep| dep.starts_with?("docker://") }

          @parsed = valid_dependencies
        rescue Psych::SyntaxError, Psych::BadAlias => e
          DependencyGraph.logger.info("parse error",
            "gh.repo.visibility" => @private_repository ? "private" : "public",
            "gh.dependency_graph.package_manager" => "actions",
            "gh.dependency_graph.manifest.type" => "workflow.yaml",
            "exception.type" => e.class.name,
            "exception.message" => e.message,
          )
          @malformed = true
          @parsed = []
        rescue StandardError => e
          DependencyGraph.logger.info("error parsing manifest",
            {
              "gh.repo.visibility" => @private_repository ? "private" : "public",
              "gh.dependency_graph.package_manager" => "actions",
              "gh.dependency_graph.manifest.type" => "workflow.yaml",
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
