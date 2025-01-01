module ManifestAdapters
  module Cargo
    module Parsers
      class Toml < ManifestAdapters::Parsers::Base

        def initialize(content)
          @content = content
        end

        def name
          parsed.dig("package", "name")
        end

        def version
          parsed.dig("package", "version")
        end

        def dependencies
          return @dependencies if defined?(@dependencies)

          @dependencies = []
          extract_scoped_dependencies(parsed).each do |entry|
            scope = entry[:scope]
            entry[:deps].each do |name, data|
              @dependencies << parse_dependency(scope, name, data)
            end
          end

          @dependencies
        rescue StandardError => e
          DependencyGraph.logger.info("error parsing manifest",
            {
              "gh.dependency_graph.package_manager" => "cargo",
              "gh.dependency_graph.manifest.type" => "cargo.toml",
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

        # There are 3 patterns in a Cargo.toml file we care about when scanning
        # for tables of scoped dependencies:
        #
        # 1. "dev-dependencies" / "dependencies" / "build-dependencies"
        # 2. "target.<platform>.{build,dev}-dependencies" / "target.<platform>.dependencies"
        # 3. "target.'<cfg_clause>'.{build,dev}-dependencies" / "target.'<cfg_clause>'.dependencies"
        #
        # Here, we attempt to identify scoped-dependency tables including these (triple-nested)
        # patterns, while attempting to short-circuit traversals that we know are dead ends.
        # https://doc.rust-lang.org/cargo/reference/manifest.html#the-manifest-format (see bottom)
        #
        # Arguments:
        # current_table - candidate for the next scoped dependency table to capture
        # depth         - 0-indexed traversal depth to limit search space
        # parent_key    - parent dependnecies table, to limit search on "target.*" traversals
        #
        # Returns: an array of { scope: <symbol>, deps: <toml_hash> } hashes
        def extract_scoped_dependencies(current_table, depth = 0, parent_key = "")
          collected = []
          return collected if depth > 2

          current_table.each do |key, value|
            # skip dead ends: sanity check the keys reference nested tables
            next unless value.is_a?(Hash)

            case key.to_s
            when "dev-dependencies"
              # can't appear in the "middle" of a nested pattern
              next if depth == 1
              collected << { scope: Types::Scope[:development], deps: value }
            when "build-dependencies"
              # can't appear in the "middle" of a nested pattern
              next if depth == 1
              collected << { scope: Types::Scope[:development], deps: value }
            when "dependencies"
              # can't appear in the "middle" of a nested pattern
              next if depth == 1
              collected << { scope: Types::Scope[:runtime], deps: value }
            when "target"
              # can only appear at the top level for nested-scope dependency table
              next if depth > 0
              (collected << extract_scoped_dependencies(value, depth + 1, key)).flatten!
            else
              # don't blindly traverse nested tables on arbitrary keys
              # unless parent is "target" (as per spec cfg/platform pattern)
              next unless parent_key == "target" && depth == 1
              (collected << extract_scoped_dependencies(value, depth + 1, key)).flatten!
            end
          end

          collected
        end

        # we need scope and other data particular to the parent manifest type
        # so we build ManifestAdapters::Manifest::Dependency records directly
        def parse_dependency(scope, dep_name, data)
          package_name, malformed_name = extract_package_name(dep_name, data)
          raw_requirements, malformed_version_spec = extract_requirements(data)
          requirements, malformed_requirements = Requirements.parse(raw_requirements)

          malformed_status = malformed_name | malformed_version_spec | malformed_requirements
          DependencyGraph.logger.info(
            "gh.dependency_graph.package_manager" => "cargo",
            "gh.dependency_graph.manifest.type" => "Cargo.toml",
            "exception.message" => "invalid or unhandled dependency record",
            "gh.dependency_graph.manifest.is_malformed" => true,
            "gh.dependency_graph.dependency.invalid_record" => "#{dep_name} => #{data}"
          ) if malformed_status

          ManifestAdapters::Manifest::Dependency.new(
            package_name: package_name,
            requirements: requirements,
            raw_requirements: raw_requirements,
            scope: scope,
            malformed: malformed_status
          )
        end

        # A Cargo dependency entry's name can be resolved as either:
        # 1. the "package" key on a Hash-typed value, if present
        # 2. the key on any-typed value (i.e. not a pkg alias)
        # https://doc.rust-lang.org/cargo/reference/specifying-dependencies.html#renaming-dependencies-in-cargotoml
        def extract_package_name(dependency_entry_name, data)
          package_name = dependency_entry_name
          if data.is_a?(Hash) && data["package"]
            return "", true if !data["package"].is_a?(String)
            package_name = data["package"]
          end

          return package_name, package_name.blank?
        end

        # A Cargo dependency entry will be expressed as either:
        # 1. a simple version String
        # 2. a Hash with a String-valued "version" key
        def extract_requirements(data)
          case data
          when String
            return data, false
          when Hash
            return data["version"] ? data["version"] : "", data["version"].blank?
          else
            return "", true
          end
        end

        def parsed
          return @parsed if defined?(@parsed)

          begin
            @parsed = Tomlrb.parse(content)
          rescue Tomlrb::ParseError, IndexError => e
            DependencyGraph.logger.info("error parsing manifest",
              "gh.dependency_graph.package_manager" => "cargo",
              "gh.dependency_graph.manifest.type" => "Cargo.toml",
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
end
