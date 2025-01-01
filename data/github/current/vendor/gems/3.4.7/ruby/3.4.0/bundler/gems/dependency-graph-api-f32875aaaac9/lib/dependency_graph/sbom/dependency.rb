module DependencyGraph
  module SBOM
    class Dependency < Struct.new(:package_manager, :package_name, :requirements, :license, :known_pinned, :attributions)
      def exact_version
        @exact_version ||=
          if known_pinned
            # The format is known to be "= ..."
            requirements[2..]
          else
            requirement_set.exact_version
          end
      end

      def requirement_set
        return @requirement_set if defined?(@requirement_set)

        valid = true
        @requirement_set = Versioning::RequirementSet.deserialize(
          requirements,
          allow_named_versions: package_manager.allows_named_versions,
          on_error: ->(range) { valid = false },
        )

        if valid
          @requirement_set
        else
          Versioning::RequirementSet.wildcard
        end
      end
    end
  end
end
