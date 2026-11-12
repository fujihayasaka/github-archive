require "json"

module ManifestAdapters
  module Composer
    module Parsers
      class ComposerJson < ManifestAdapters::Parsers::Base
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
            # composer manifests should be a hash, not an array encapsulating a hash
            # doesn't throw a parse exception because it technically is valid JSON
            @is_json_array = true
            @json = {}
            return
          end

          # If there packages listed in this file, it is a composer.lock and not a composer.json
          @lockfile_packages_listed = @json["packages"].present? || @json["packages-dev"].present?
        end

        def malformed?
          @json_exception || @empty || @lockfile_packages_listed || @is_json_array
        end

        def name
          @json["name"] # name isn't required, only for published packages
        end

        def version
          @json["version"] # version is almost always omitted, but can be defined
        end

        def dependencies
          return [] if @json["require"].blank? && @json["require-dev"].blank?

          mapped_dependencies(:runtime, @json["require"]) +
            mapped_dependencies(:development, @json["require-dev"])
        end

        def mapped_dependencies(scope, dependencies)
          return [] if dependencies.blank? || !dependencies.is_a?(Hash) # composer json schema denotes that require and require-dev should be a hash of dependencies
          dependencies.map do |dependency, version|
            if dependency.is_a?(String) && version.is_a?(String)
              resolved_reqs = ManifestAdapters::Composer::Requirements.parse(version)
              resolved_scope = ManifestAdapters::Composer.parse_scope(scope)
              # TODO: failures to resolve version and scope should also be cause for "malformed" status!
              is_malformed = dependency.blank? || version.blank? || !dependency.is_a?(String) || !version.is_a?(String)

              ManifestAdapters::Manifest::Dependency.new(
                package_name: dependency,
                requirements: resolved_reqs,
                raw_requirements: version,
                scope: resolved_scope,
                malformed: is_malformed,
              )
            end
          end.compact
        end
      end
    end
  end
end
