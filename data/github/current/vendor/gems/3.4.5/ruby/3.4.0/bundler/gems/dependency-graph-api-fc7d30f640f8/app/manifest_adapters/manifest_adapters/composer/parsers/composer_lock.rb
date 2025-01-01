require "json"

module ManifestAdapters
  module Composer
    module Parsers
      class ComposerLock < ManifestAdapters::Parsers::Base
        def initialize(content)
          @empty = content.blank?
          @json_exception = false
          @json =
            begin
              JSON.parse(content)
            rescue JSON::ParserError => e
              @json_exception = true
              {}
            end

          unless @json.is_a?(Hash)
            # composer manifests should not be a hash, not an array encapsulating a hash
            # doesn't throw a parse exception because it technically is valid JSON
            @is_json_array = true
            @json = {}
            return
          end

          # A composer.lock with dependencies should have a list of packages and/or development packages
          @packages_listed = @json["packages"].present? || @json["packages-dev"].present?
        end

        def malformed?
          @json_exception || @empty || !@packages_listed || @is_json_array
        end

        def name
          "" # name doesn't exist in composer lockfile
        end

        def version
          "" # version doesn't exist in composer lockfile
        end

        def dependencies
          return [] if @json["packages"].blank? && @json["packages-dev"].blank?

          mapped_dependencies(:runtime, @json["packages"]) +
            mapped_dependencies(:development, @json["packages-dev"])
        end

        def mapped_dependencies(scope, dependencies)
          return [] if dependencies.blank?
          dependencies.map do |dependency|
            version = dependency["version"].to_s

            # try to convert a branch alias to the aliased version if it's defined in the lockfile
            if version.start_with?("dev-") && dependency&.dig("extra", "branch-alias").is_a?(Hash) && dependency&.dig("extra", "branch-alias", version)
              version = dependency&.dig("extra", "branch-alias", version)
            end

            resolved_reqs = ManifestAdapters::Composer::Requirements.parse(version)
            resolved_scope = ManifestAdapters::Composer.parse_scope(scope)
            # TODO: failures to resolve version and scope should also be cause for "malformed" status!
            is_malformed = dependency["name"].blank? || dependency["version"].blank?

            ManifestAdapters::Manifest::Dependency.new(
              package_name: dependency["name"],
              requirements: resolved_reqs,
              raw_requirements: version,
              scope: resolved_scope,
              malformed: is_malformed,
            )
          end
        end
      end
    end
  end
end
