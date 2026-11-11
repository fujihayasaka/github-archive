
module ManifestAdapters
  module Npm
    module Parsers
      class PackageJsonLockParser < PackageJsonParser
        def dependencies
          lockfileVersion = parsed.fetch("lockfileVersion", 1)
          if lockfileVersion == 3
            dependencies_v3
          else
            dependencies_v1
          end
        end

        def dependencies_v1
          aggregated = []
          process_queue = Array(parsed["dependencies"])
          while process_queue.length > 0 do
            package_name, attrs = process_queue.pop
            package_dep = {
              package_name: package_name,
              scope: runtime_scope,
              requirements: nil,
            }

            # dependencies having content implies that the requires statement
            # in the attrs node is pointing to an "overridden" version of the
            # package used elsewhere. This is only used in multiversion
            # scenarios (for the same package). We don't care about the
            # requires attribute, we just need to collect all dependencies.
            # We need to process N-level dependencies, too, e.g.:
            # https://github.com/npm/cli/blob/940ba878019e7b35bda20a26baaa4c99bebc906b/package-lock.json#L12040
            if attrs.is_a?(Hash) && attrs["dependencies"].present?
              attrs["dependencies"].each do |inner_name, inner_attrs|
                process_queue.push([inner_name, inner_attrs])
              end
            end

            # Extract requirements and scope out of attribute hash
            # Only if its a valid hash, otherwise the requirements are invalid,
            # and this package dependency is malformed.
            if attrs.kind_of?(Hash)
              package_dep[:requirements] = attrs["version"]
              package_dep[:scope] = (attrs["dev"] ? development_scope : runtime_scope)
            end

            aggregated << dependency(**package_dep)
          end

          aggregated
        end

        def dependencies_v3
          parsed["packages"].filter_map do |path, attrs|
            # `path` will be of the form `node_modules/{package_name}` for direct dependencies,
            # and `node_modules/{some_package}/node_modules/{package_name}` for indirect dependencies
            # (or further nested). Namespaced packages will be further nested, e.g. `node_modules/@foo/bar`.
            package_name = path.split("node_modules/").last
            version = attrs["version"]
            next unless package_name.present? && version.present?
            dependency(
              package_name: package_name,
              scope: attrs["dev"] ? development_scope : runtime_scope,
              requirements: attrs["version"]
            )
          end
        end

        private

        def runtime_scope
          Types::Scope[:runtime]
        end

        def development_scope
          Types::Scope[:development]
        end
      end
    end
  end
end
