require "open3"

module ManifestAdapters
  module Go
    # GoModParser is the parser for go.mod files.
    # See ../../../../spec/manifest_adapters/go/go_mod_parser_spec.rb for test.
    # For an overview, see "Go module support in Dependency Graph",
    # ../../../../docs/go-modules.md
    class GoModParser < ManifestAdapters::Parsers::Base
      # We always leave the Manifest.dependent_name field blank,
      # because its purpose (IIUC) is to participate in the
      # package-to-repo mapping, which, by default, joins the
      # packages and manifests tables to find the repo that
      # provides the manifest that defines a given package.
      #
      # But for Go, the package's repo is computed authoritatively
      # by a specialized package-to-repo mapping function that uses
      # the HTTP-based go-import mechanism.
      # (A module declaration in a go.mod file defines an importable
      # module only if the go-import meta tag obtained from
      # https://$module?go-get=1 matches the provenance of this file:
      # https://github.com/owner/repository, where owner and
      # repository come from self.repository_nwo. There is no way to
      # compute the correct result even approximately without that
      # mechanism.)
      #
      # So, we have no need of the Manifest.dependent_name field.
      # Rather than populate it incorrectly, we leave it blank.
      #
      # TODO(adonovan): We could eliminate the whole concept of
      # package-to-repo mapping if we make package ingestion
      # responsible for reporting the Git (or other VCS) repo
      # that hosts the package; presumably most (all?) package
      # managers provide this information. See discussion in
      # https://github.com/github/dependency-graph-api/issues/1999#issuecomment-859147310
      def name
        "" # sic, not modfile["Module"]["Path"]
      end

      # The version of a Go module comes from the git tags, not the manifest itself.
      # In any case, this field is neither saved in the database nor used by
      # current clients of the parsed_manifest GraphQL interface.
      def version; end

      def initialize(content)
        @content = content
        @malformed = false
      end

      def dependencies
        @dependencies ||= parse_dependencies
      end

      def malformed?
        !!@malformed
      end

      private
      # parses a go.mod file and returns dependencies.
      def parse_dependencies
        # Fork+exec the go/ecosystem/go/gomod2json Go executable to
        # convert the go.mod file to JSON. (An executable must have
        # been built in the working directory; see the root Dockerfile.)
        #
        # capture3 may raise an exception on failure to exec (e.g. Errno::ENOENT,
        # indicating application misconfiguration) or due to internal errors
        # (e.g. Errno::EMFILES, too many open files).
        # For now, treat both as application errors: unhandled exceptions.
        #
        # The binmode=true is required to disable the manipulations and conversions
        # ordinarily done by IO.pipe, which would cause capture3 to crash when
        # writing a ASCII-8BIT-tagged string containing valid UTF-8 (!).
        out, err, status = Open3.capture3("./gomod2json", stdin_data: @content, binmode: true)
        if status != 0
          # A non-zero exit indicates an application bug or OOM.
          # Treat it equivalent to an unhandled exception in this Ruby code.
          @malformed = true
          raise "go.mod parser failed: #{err}"
        end

        # Parse JSON output. See Result type in gomod2json.go for schema.
        begin
          result = JSON.parse(out)
        rescue JSON::ParserError => e
          # Ill-formed JSON indicates an application bug.
          # Treat it equivalent to an unhandled exception in this Ruby code.
          @malformed = true
          raise "gomod2json produced invalid JSON: #{e}"
        end

        dependencies = []

        if result["Errors"]
          # Parse errors in go.mod.
          # Bad user input is a not a bug, but keep count.
          raise "malformed file encountered, error: #{result['Errors']}"
        else
          # File is valid.
          modfile = result["ModFile"]

          require = modfile["Require"]
          if require
            dependencies = require.map do |req|
              version = req["Version"].delete_prefix("v")
              ManifestAdapters::Manifest::Dependency.new(
                package_name: req["Path"],
                # Go module versions are SemVer-compatible;
                # see https://golang.org/doc/modules/version-numbers.
                requirements: "= " + version,
                raw_requirements: version,
                scope: Types::Scope[:runtime],
                malformed: false,
              )
            end
          end
        end

        if DependencyGraph.flipper[:dependency_graph_go_mod_replace].enabled?
          dependencies = apply_replacements(dependencies, modfile["Replace"])
          dependencies = apply_tools(dependencies, modfile["Tool"])
        else
          dependencies
        end
      end

      # apply_tools returns the dependencies with the given tools, which
      # should be the "Tool" section of the parsed go.mod file.
      def apply_tools(dependencies, modfile_tool)
        if modfile_tool.nil? || modfile_tool.empty?
          return dependencies
        end

        tools = Set.new
        modfile_tool.each do |tool|
          tools << tool["Path"]
        end

        final_deps = []
        dependencies.each do |dependency|
          if dependency.malformed?
            final_deps << dependency
            next
          end

          if tools.include?(dependency.package_name)
            final_deps << ManifestAdapters::Manifest::Dependency.new(
              package_name: dependency.package_name,
              requirements: dependency.requirements,
              raw_requirements: dependency.raw_requirements,
              scope: Types::Scope[:development],
              malformed: false
            )
          else
            final_deps << dependency
          end
        end
        final_deps
      end

      # apply_replacements returns the dependencies with the given replacements, which
      # should be the "Replace" section of the parsed go.mod file.
      def apply_replacements(dependencies, modfile_replace)
        if modfile_replace.nil? || modfile_replace.empty?
          return dependencies
        end

        final_deps = []
        replacements = GoModReplacements.new(modfile_replace)
        dependencies.each do |dependency|
          if dependency.malformed?
            final_deps << dependency
            next
          end

          replacement = replacements.find_replacement(dependency)
          if replacement
            final_deps << replacement
          else
            final_deps << dependency
          end
        end

        final_deps
      end
    end

    class GoModReplacements
      def initialize(replacements)
        @replacements = replacements.map do |entry|
          GoModReplacement.new(entry.first, entry.second)
        end
      end

      def find_replacement(dependency)
        @replacements.each do |replacement|
          return replacement.replacement_for(dependency) if replacement.match?(dependency)
        end
        nil
      end
    end

    class GoModReplacement
      def initialize(target, replacement)
        @target = target
        @replacement = replacement
        @target_path = target["Path"]
        @target_version = (target["Version"] || "").delete_prefix("v")
        @replacement_path = replacement["Path"] || ""
        @replacement_version = (replacement["Version"] || "").delete_prefix("v")
      end

      def match?(dependency)
        raise ArgumentError, "dependency must be a ManifestAdapters::Manifest::Dependency" unless dependency.is_a?(ManifestAdapters::Manifest::Dependency)

        return false if dependency.malformed?
        return false unless dependency.package_name == @target_path
        return true if @target_version.empty?

        dependency.raw_requirements == @target_version
      end

      def replacement_for(dependency)
        raise ArgumentError, "dependency must be a ManifestAdapters::Manifest::Dependency" unless dependency.is_a?(ManifestAdapters::Manifest::Dependency)
        new_requirements = @replacement_version.empty? ? dependency.requirements : "= " + @replacement_version
        new_raw_requirements = @replacement_version.empty? ? dependency.raw_requirements : @replacement_version

        ManifestAdapters::Manifest::Dependency.new(
          package_name: @replacement_path,
          requirements: new_requirements,
          raw_requirements: new_raw_requirements,
          scope: dependency.scope,
          malformed: false
        )
      end
    end
  end
end
