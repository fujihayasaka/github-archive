# frozen_string_literal: true
require "json"

module ManifestAdapters
  module Npm
    module SnapshotParsers
      # as it reads on the tin. this is the max length of any NPM registered package name
      MAX_NPM_PACKAGE_NAME_LENGTH = 214

      # label that differentiates this from build-time submissions/detectors
      LOCKFILE_DETECTOR = "GitHub Dependabot Push-Time Snapshot"
      DETECTOR_VERSION_STUB = "0.1.0"
      DETECTOR_URL_STUB = "https://github.com/github"

      # enum values used frequently in snapshot package entries and NPM lockfiles
      NODE_MODULES_LABEL = "node_modules"
      RELATIONSHIP_UNKNOWN = ""
      RELATIONSHIP_DIRECT = "direct"
      RELATIONSHIP_INDIRECT = "indirect"
      SCOPE_RUNTIME = "runtime"
      SCOPE_DEVELOPMENT = "development"

      # NPM manifest "version" entries can be exact versions or
      # range specs that we care about, as well as a bunch of
      # path and URL-based flavors we want to filter out
      VALID_VERSION_PREFIX = /^\s*(\*|x)|((([\^~])|([><]=)|[><])?\s*\d+)/
      VALID_EXACT_VERSION_PREFIX = /^\s*\d+/

      # contextual error types
      class MalformedLockfileError < StandardError; end
      class MalformedManifestError < StandardError; end
      class MalformedEventError < StandardError; end
      class SnapshotPopulationError < StandardError; end

      # basic snapshot scaffold to be populated (or not, in the delete case!)
      def self.base_snapshot(hydro_message)
        # https://github.com/github/github/blob/master/app/api/description/components/schemas/snapshot.yaml
        {
          version: 0,
          detector: {
            name: LOCKFILE_DETECTOR,
            version: DETECTOR_VERSION_STUB,
            url: DETECTOR_URL_STUB,
          },
          job: {
            correlator: build_correlator(hydro_message),
            id: "#{hydro_message[:snapshot_metadata][:push_id]}",
          },
          internal: true,
          scanned: Time.at(hydro_message[:manifest_file][:pushed_at][:seconds]).to_datetime,
          sha: hydro_message[:snapshot_metadata][:commit_sha].to_s,
          ref: hydro_message[:snapshot_metadata][:ref].to_s,
          manifests: {},
        }
      end

      def self.build_correlator(hydro_message)
        repo_id = hydro_message[:repository_id]
        raise MalformedEventError.new("invalid repository ID on event") unless repo_id
        fullpath = manifest_full_path(hydro_message)

        "#{repo_id}:#{fullpath}"
      end

      def self.manifest_full_path(hydro_message)
        filename = hydro_message.dig(:manifest_file, :filename)
        path = hydro_message.dig(:manifest_file, :path)
        raise MalformedEventError.new("invalid empty filename") if filename.to_s.blank?

        return filename if path.to_s.blank?
        File.join(path, filename)
      end

      # IMPORTANT! This is a DS-API PoC and does NOT meet the
      # ManifestAdapters::Parsers::Base contract!
      class PackageLockJson
        def initialize(content:, hydro_message:, associated_content: nil)
          # the lockfile content required to submit a snapshot
          @lockfile_content = content
          # for lockfile versions 1 or older, the associated package.json blob
          # must also be analyzed to differentiate directs vs transitives :(
          @associated_content = associated_content

          # not the whole "raw" Hydro message! Just the unwrapped event data:
          # https://hydro.githubapp.com/kafka/clusters/potomac/topic?tab=schema&topic=cp1-iad.ingest.github.dependencygraph.v1.RepositoryManifestFileChange
          @hydro_message = hydro_message
          # populated on successful call to PackageLockJson#parse
          @snapshot = nil

          raise MalformedLockfileError.new("missing lockfile content") if @lockfile_content.blank?
          if @hydro_message.blank? || @hydro_message[:manifest_file].blank?
            raise MalformedEventError.new("invalid Hydro event")
          end
          if @hydro_message[:snapshot_metadata].blank?
            DependencyGraph.logger.warn("Hydro event missing snapshot metadata",
              "gh.repo.id" => @hydro_message[:repository_id],
              "gh.repo.owner_id" => @hydro_message[:owner_id],
              "gh.repo.name_with_owner" => @hydro_message[:repository_nwo],
              "gh.dependency_graph.snapshot.metadata" => @hydro_message[:snapshot_metadata].to_s)
            raise MalformedEventError.new("Hydro event missing snapshot metadata")
          end
        end

        attr_reader :snapshot

        # project name as declared in the lockfile
        def name
          parsed["name"].to_s
        end

        # project version as declared in the lockfile
        def version
          parsed["version"].to_s
        end

        # indicates the flavor of lockfile schema we'll be parsing
        def lockfile_version
          parsed["lockfileVersion"].to_i
        end

        def with_requires
          !!parsed["requires"]
        end

        # parses the lockfile in version-aware manner, taking
        # advantage of whatever supplementary metadata is available
        # from the change event
        def parse
          # raise JSON error if the lockfile is corrupted
          parsed

          # version clause can be absent from valid lockfile
          if name.length >= MAX_NPM_PACKAGE_NAME_LENGTH
            raise MalformedLockfileError.new("lockfile project 'name' field exceeds NPM max valid length")
          end

          tags = base_tags
          if lockfile_version > 1 && parsed["packages"].present?
            # expects full-featured lockfile v2+ input
            parse_packages
          elsif @associated_content.present? && !parsed_associated.empty?
            # expects legacy lockfile version + associated parent manifest
            tags = tags.merge({ parse_type: "with_assoc_manifest" })
            parse_dependencies
          else
            # best-effort legacy lockfile parse without supplemental metadata
            tags = tags.merge({ parse_type: "best_effort" })
            parse_dependencies_fallback
          end
          raise SnapshotPopulationError.new unless snapshot

          manifests_count = snapshot[:manifests]&.keys&.count || 0
          Instrument.count("etl.manifest_snapshot.parser.manifests.processed", manifests_count, **tags)
          resolved_count = snapshot[:manifests]&.values&.map { |m| m[:resolved].keys.count }&.sum || 0
          Instrument.count("etl.manifest_snapshot.parser.dependencies.processed", resolved_count, **tags)

          self
        end

        private

        # this parses recent (v2+) lockfile versions into well-formed snapshot
        # submissions. no supplimental metadata is required to fully resolve the
        # dependency tree and exact package versions.
        # https://docs.npmjs.com/cli/v8/configuring-npm/package-lock-json#packages
        def parse_packages
          if parsed.dig("packages", "").nil?
            raise MalformedLockfileError.new("expected lockfile v2+ 'packages' entry missing")
          end

          snapshot = build_snapshot_payload

          # collect all direct dependencies for downstream decision step
          directs = {
            runtime: parsed.dig("packages", "", "dependencies")&.keys || [],
            development: parsed.dig("packages", "", "devDependencies")&.keys || [],
          }

          resolved = {}
          parsed["packages"].each do |pkg_path, pkg_meta|
            # the empty package "" is the project root and is expected
            next if pkg_path.strip.empty?

            entry = {}

            pkg_name = extract_package_name(pkg_path)
            if pkg_name.length >= MAX_NPM_PACKAGE_NAME_LENGTH
              Instrument.increment(
                "etl.manifest_snapshot.parser.dependencies.warnings",
                **tags_with_error("max_pkg_name_length"))
              next
            end

            entry[:relationship] = resolve_package_relationship(directs, pkg_path, pkg_name, pkg_meta)
            entry[:scope] = is_dev_package(pkg_meta) ? SCOPE_DEVELOPMENT : SCOPE_RUNTIME
            entry[:metadata] = { license: pkg_meta["license"] } if pkg_meta["license"]

            unless pkg_meta["version"]&.match(VALID_EXACT_VERSION_PREFIX)
              Instrument.increment(
                "etl.manifest_snapshot.parser.dependencies.warnings",
                **tags_with_error("invalid_exact_version"))

              DependencyGraph.logger.warn("invalid exact version prefix",
                "code.function" => "parse_packages",
                "code.namespace" => self.class.name,
                "gh.dependency_graph.manifest.filename" => @hydro_message[:manifest_file][:filename],
                "gh.dependency_graph.manifest.path" => @hydro_message[:manifest_file][:path],
                "gh.repo.id" => @hydro_message[:repository_id],
                "gh.repo.owner_id" => @hydro_message[:owner_id],
                "gh.repo.name_with_owner" => @hydro_message[:repository_nwo],
                "gh.dependency_graph.manifest.is_invalid" => true,
                "gh.dependency_graph.package.name" => pkg_name,
                "gh.dependency_graph.package.version" => pkg_meta["version"])

              next
            end
            entry[:package_url] = to_purl(pkg_name, pkg_meta["version"])

            # if this package entry lists version range requirements
            # for its direct dependencies, resolve those to pinned
            # versions from the lockfile "packages" list
            entry[:dependencies] = resolve_package_dependency_versions(pkg_path, pkg_meta["dependencies"])

            # capture well-formed dependency entry including scope and transitive meta
            resolved[entry[:package_url]] = entry
          end

          # capture the fully populated package entry list
          snapshot[:manifests][manifest_key][:resolved] = resolved

          # if all went well, capture this in instance var
          @snapshot = snapshot
        end

        # this parses lockfiles prior to version 2 into well-formed snapshot submissions.
        # this format is lossy and requires supplimental metadata:
        # 1. the associated "package.json" file to resolve direct vs. transitive
        # 2. package-level "requires" clauses to fully resolve the dependency tree relationships
        # https://docs.npmjs.com/cli/v8/configuring-npm/package-lock-json#dependencies
        def parse_dependencies
          snapshot = build_snapshot_payload

          # collect all direct dependencies for downstream decision step
          directs = {
            runtime: parsed_associated["dependencies"]&.keys || [],
            development: parsed_associated["devDependencies"]&.keys || [],
          }
          # cache all exact versions found, by package name
          cached = {}
          # the output list to be submitted with the snapshot;
          # "requires" meta is also temporarily cached here
          # and stripped later
          resolved = {}

          parsed["dependencies"].to_h.each do |pkg_name, pkg_meta|
            if pkg_name.length >= MAX_NPM_PACKAGE_NAME_LENGTH
              Instrument.increment(
                "etl.manifest_snapshot.parser.dependencies.warnings",
                **tags_with_error("max_pkg_name_length"))
              next
            end
            entry = {}

            entry[:relationship] = resolve_legacy_package_relationship(directs, pkg_name, pkg_meta)
            entry[:scope] = is_dev_package(pkg_meta) ? SCOPE_DEVELOPMENT : SCOPE_RUNTIME

            unless pkg_meta["version"]&.match(VALID_EXACT_VERSION_PREFIX)
              Instrument.increment(
                "etl.manifest_snapshot.parser.dependencies.warnings",
                **tags_with_error("invalid_exact_version"))
              next
            end
            entry[:package_url] = to_purl(pkg_name, pkg_meta["version"])

            # temporarily cache each package declaration's "requires" list of
            # version specs on the package's snapshot entry itself
            entry[:requires] = pkg_meta["requires"]

            # capture a cache of all resolved (exact version) packages
            # present in the lockfile; used downstream to resolve "requires"
            # clauses into exact dep tree, if present in the lockfile
            cached[pkg_name] = [] if !cached[pkg_name]
            cached[pkg_name] << pkg_meta["version"]

            # nested dependencies in the old lockfile format are declared recursively
            # and follow the same format as top-level "dependencies" entries.
            # nested declarations are only present when the parent package requires
            # a version of a dependency that is not already resolved at a higher
            # tier of the full dependency tree. This has two effects:
            # 1. recursive traversal in the call below will side-effect the append of nested entries to "resolved"
            # 2. a "requires" entry is needed to map deduped (shared) package versions to the current package
            entry[:dependencies] = resolve_legacy_package_dependencies(resolved, cached, pkg_meta)

            # capture well-formed dependency entry including scope and transitive meta
            resolved[entry[:package_url]] = entry
          end

          # use the fully populated cache of packages to exact versions to
          # resolve the missing part of the full dependency tree from
          # the per-package "requires" list of version ranges
          resolve_legacy_requires_ranges(resolved, cached)
          resolved.values.each { |entry| entry.except!(:requires) }

          # capture the fully populated package entry list
          snapshot[:manifests][manifest_key][:resolved] = resolved

          @snapshot = snapshot
        end

        # This is a best-effort attempt to parse older lockfiles without additional metadata
        # to disambiguate direct vs. indirect relationships
        def parse_dependencies_fallback
          snapshot = build_snapshot_payload

          resolved = {}
          cached = {}
          parsed["dependencies"].to_h.each do |pkg_name, pkg_meta|
            if pkg_name.length >= MAX_NPM_PACKAGE_NAME_LENGTH
              Instrument.increment(
                "etl.manifest_snapshot.parser.dependencies.warnings",
                **tags_with_error("max_pkg_name_length"))
              next
            end

            unless pkg_meta["version"]&.match(VALID_EXACT_VERSION_PREFIX)
              Instrument.increment(
                "etl.manifest_snapshot.parser.dependencies.warnings",
                **tags_with_error("invalid_exact_version"))
              next
            end

            # capture a cache of all resolved (exact version) packages
            # present in the lockfile; used downstream to resolve "requires"
            # clauses into exact dep tree, if present in the lockfile
            cached[pkg_name] = [] if !cached[pkg_name]
            cached[pkg_name] << pkg_meta["version"]

            # initial pass at new entry
            entry = {
              package_url: to_purl(pkg_name, pkg_meta["version"]),
              scope: is_dev_package(pkg_meta) ? SCOPE_DEVELOPMENT : SCOPE_RUNTIME,
              relationship: RELATIONSHIP_UNKNOWN, # initialize as "unknown" and resolve sure cases elsewhere
              requires: pkg_meta["requires"], # temporarily cache unresolved "requires" version ranges
              dependencies: resolve_legacy_package_dependencies(resolved, cached, pkg_meta)
            }

            resolved[entry[:package_url]] = entry
          end

          # use the fully populated cache of packages to exact versions to
          # resolve the missing part of the full dependency tree from
          # the per-package "requires" list of version ranges
          resolve_legacy_requires_ranges(resolved, cached)
          resolved.to_h.values.each { |entry| entry.except!(:requires) }

          # if per-package "requires" entries are present on the lockfile,
          # we can make a best-effort attempt to classify direct deps:
          # 1. collect all "dependencies" PURLs from the snapshot (known transitives)
          # 2. compare "dependencies" PURLs to top-level keys in "resolved" list
          # 3. a "resolved" package that isn't referenced in "dependencies" is a direct
          if parsed["requires"]
            transitives = Set.new(resolved.values.map { |v| v[:dependencies] }.flatten.compact)
            resolved.each do |purl, pkg_data|
              pkg_data[:relationship] = RELATIONSHIP_DIRECT if !transitives.include?(purl)
            end
          end

          # capture the fully populated package entry list
          snapshot[:manifests][manifest_key][:resolved] = resolved

          @snapshot = snapshot
        end

        # this parses "package-lock.json" files for reshaping into snapshot submissions
        def parsed
          return @parsed if defined?(@parsed)

          @parsed = begin
            parsed = JSON.parse(@lockfile_content)
            parsed.is_a?(Hash) ? parsed : {}
          rescue JSON::ParserError => je
            raise MalformedLockfileError.new("failed parsing JSON: #{je}")
          end
        end

        # this parses the "package.json" file associates with the lockfile
        # being submitted as a snapshot. The parent manifest is only required
        # to resolve direct dependencies on lockfile versions prior to v2
        def parsed_associated
          return @parsed_associated if defined?(@parsed_associated)
          return @parsed_associated = {} if @associated_content.nil?

          @parsed_associated = begin
            parsed_associated = JSON.parse(@associated_content)
            parsed_associated.is_a?(Hash) ? parsed_associated : {}
          rescue JSON::ParserError => je
            raise MalformedManifestError.new("failed parsing JSON: #{je}")
          end
        end

        # return a generic, well-formed snapshot payload hash ready to populate
        def build_snapshot_payload
          # https://github.com/github/github/blob/master/app/api/description/components/schemas/snapshot.yaml
          fullpath = ManifestAdapters::Npm::SnapshotParsers.manifest_full_path(@hydro_message)
          base = ManifestAdapters::Npm::SnapshotParsers.base_snapshot(@hydro_message)

          # set up manifest file entry to be populated
          base[:manifests] = {
            fullpath.to_sym => {
              name: @hydro_message[:manifest_file][:filename].to_s,
              metadata: {
                project_name: name,
                project_version: version,
                license: project_license,
              },
              file: {
                source_location: fullpath,
              },
              resolved: {},
            },
          }

          base
        end

        # manifest_full_path symbolized - used as key in the snaphot's  "manifests" hash
        def manifest_key
          ManifestAdapters::Npm::SnapshotParsers.manifest_full_path(@hydro_message).to_sym
        end

        def to_purl(pkg_name, pkg_version)
          PackageUrls::PackageUrl.from_package_release(
              package_manager: Types::PackageManager[:npm],
              name: pkg_name,
              version: pkg_version).to_purl
        end

        def project_license
          if lockfile_version > 1 && parsed["packages"].present?
            (parsed["license"] || parsed.dig("packages", "", "license")).to_s
          else
            parsed_associated["license"].to_s
          end
        end

        def is_dev_package(pkg_meta)
          !!(pkg_meta["dev"] || pkg_meta["devOptional"])
        end

        def tags_with_error(error_type)
          base_tags.merge({ error_type: "#{error_type}" })
        end

        def base_tags
          {
            package_manager: "#{Types::PackageManager[:npm]}",
            manifest_type: "#{Types::Manifest[:package_lock_json]}",
            lockfile_version: "#{lockfile_version}",
            with_requires: "#{with_requires}",
          }
        end

        # ###################################
        # utility methods for parse_packages
        # ###################################

        # determine the direct/indirect (transitive) relationship of this package
        # to the project, based on the "packages" entry key. this key describes
        # the package's relationship to the project dependency tree:
        # 1. A key with a single "node_modules/<package>" clause might be a direct dep
        # 2. A key with 2 or more node_modules clauses is an indirect dep
        def resolve_package_relationship(directs, pkg_path, pkg_name, pkg_meta)
          relationship = nil
          if count_package_nesting(pkg_path) == 1
            # for single "node_modules/@namespace/foo" entries, could be direct or transitive
            if (is_dev_package(pkg_meta) && directs[:development].include?(pkg_name)) ||
                (!is_dev_package(pkg_meta) && directs[:runtime].include?(pkg_name))
              relationship = RELATIONSHIP_DIRECT
            else
              relationship = RELATIONSHIP_INDIRECT
            end
          else
            # multiple node_modules segments in "packages" key indicates transitive by nature
            relationship = RELATIONSHIP_INDIRECT
          end

          relationship
        end

        # map each of the parent package's dependency version
        # range specs to the most specific resolved version
        # present in the lockfile's "packages" list
        def resolve_package_dependency_versions(parent_pkg_key, raw_deps)
          raw_deps&.map { |pkg_name, vspec|
            if vspec.strip.match(VALID_EXACT_VERSION_PREFIX)
              # easy case - capture exact version in PURL
              to_purl(pkg_name, vspec)
            else
              # ugly case - traverse the "packages" tree from leaf
              # to root, trying to map the target range to the most
              # specificly pathed resolved version found
              unless vspec.match(VALID_VERSION_PREFIX)
                Instrument.increment(
                  "etl.manifest_snapshot.parser.dependencies.warnings",
                  **tags_with_error("invalid_version_range"))

                DependencyGraph.logger.warn("invalid version range prefix",
                  "gh.dependency_graph.manifest.is_malformed" => true,
                  "code.function" => "resolve_package_dependency_versions",
                  "gh.repo.id" => @hydro_message[:repository_id],
                  "gh.repo.owner_id" => @hydro_message[:owner_id],
                  "gh.dependency_graph.manifest.filename" => @hydro_message[:manifest_file][:filename],
                  "gh.dependency_graph.manifest.path" => @hydro_message[:manifest_file][:path],
                  "gh.repo.name_with_owner" => @hydro_message[:repository_nwo],
                  "gh.dependency_graph.package.name" => pkg_name,
                  "gh.dependency_graph.package.version" => vspec)

                next nil
              end

              resolved = nil
              parent_tree = parent_pkg_key.dup
              while resolved.nil? do
                target_key = if parent_tree.empty?
                               "#{NODE_MODULES_LABEL}/#{pkg_name}"
                             else
                               "#{parent_tree}/#{NODE_MODULES_LABEL}/#{pkg_name}"
                             end
                resolved = parsed.dig("packages", target_key, "version")

                # remove trailing "/node_modules/<pkg_name>" clause from
                # target_key for next (more generalized) lookup attempt
                cut_point = parent_tree.rindex(/node_modules/)
                break if cut_point.nil?
                parent_tree = parent_tree[0...cut_point].chomp("/")
              end

              # return the PURL with resolved version if found
              Instrument.increment(
                "etl.manifest_snapshot.parser.requires.warnings",
                **tags_with_error("unresolved_exact_version")) unless resolved
              resolved ? to_purl(pkg_name, resolved) : nil
            end
          }.to_a.compact
        end

        # package-lock.json "packages" element keys illustrate the entire dep tree
        def count_package_nesting(pkg_path)
          count = 0
          pkg_path.split("/").each do |elem|
            count += 1 if elem.strip == NODE_MODULES_LABEL
          end

          count
        end

        # transitives listed under "packages" clause include full nested path
        def extract_package_name(pkg_path)
          pkg_path.gsub(/^.*\/?node_modules\//, "")
        end

        # recover an unescaped NPM "namespace/name" from a well-formed PURL string
        def ns_and_name_from_purl(purlstr)
          # note: only compatible with NPM style PURLs due to "/" separator
          PackageUrls::PackageUrl.from_purl(purl: purlstr).namespace_with_name("/")
        end

        # #######################################
        # utility methods for parse_dependencies
        # #######################################

        # if a package in the "dependencies" object is not nested, it could be a direct
        # dep of the project. In those cases, we check against the directs declared in
        # the asscoiated package.json to decide. nested "dependencies" entries are
        # always indirect
        def resolve_legacy_package_relationship(directs, pkg_name, pkg_meta)
          # without "requires" entries we can't just delcare all non-directs
          # as RELATIONSHIP_INDIRECT, or many transitives will be "parentless"
          # (not tied back to the full dependency tree) and won't surface in
          # the UI once we aren't using DG-API package tables to surface
          # transitive/nested deps any more.
          relationship = with_requires ? RELATIONSHIP_INDIRECT : RELATIONSHIP_UNKNOWN
          if (is_dev_package(pkg_meta) && directs[:development].include?(pkg_name)) ||
              (!is_dev_package(pkg_meta) && directs[:runtime].include?(pkg_name))
            relationship = RELATIONSHIP_DIRECT
          end

          relationship
        end

        # flatten nested "dependencies" entries (transitive deps) into top-level
        # list for post-processing and snapshot submission
        def resolve_legacy_package_dependencies(resolved, cached, parent_pkg_meta)
          dependencies = []
          parent_pkg_meta["dependencies"].to_a.each do |pkg_name, pkg_meta|
            if pkg_name.length >= MAX_NPM_PACKAGE_NAME_LENGTH
              Instrument.increment(
                "etl.manifest_snapshot.parser.dependencies.warnings",
                **tags_with_error("max_pkg_name_length"))
              next
            end

            unless pkg_meta["version"]&.match(VALID_EXACT_VERSION_PREFIX)
              Instrument.increment(
                "etl.manifest_snapshot.parser.dependencies.warnings",
                **tags_with_error("invalid_exact_version"))

              DependencyGraph.logger.warn(
                message: "invalid exact version prefix",
                metric: "etl.manifest_snapshot.parser.dependencies.warnings",
                errortag: "invalid_exact_version",
                method: "resolve_legacy_package_dependencies",
                repository_id: @hydro_message[:repository_id],
                owner_id: @hydro_message[:owner_id],
                filename: @hydro_message[:manifest_file][:filename],
                path: @hydro_message[:manifest_file][:path],
                nwo: @hydro_message[:repository_nwo],
                raw_package: pkg_name,
                raw_version: pkg_meta["version"])

              next
            end
            purl = to_purl(pkg_name, pkg_meta["version"])
            dependencies << purl

            # used downstream to resolve "requires" clauses
            cached[pkg_name] = [] if !cached[pkg_name]
            cached[pkg_name] << pkg_meta["version"]

            resolved[purl] = {
              package_url: purl,
              relationship: RELATIONSHIP_INDIRECT,
              scope: is_dev_package(pkg_meta) ? SCOPE_DEVELOPMENT : SCOPE_RUNTIME,
              requires: pkg_meta["requires"], # removed before final snapshot stored
              dependencies: resolve_legacy_package_dependencies(resolved, cached, pkg_meta)
            }
          end

          dependencies
        end

        # resolve each package's "requires" list of version ranges to an
        # exact-version PURL in the package's "dependencies" entry
        def resolve_legacy_requires_ranges(resolved, cached)
          # convert the cache of package names to exact versions into
          # a deduplicated, desc-sorted list of RequirementSets we can
          # compare against "requires" version specs
          cached.keys.each do |pkg_name|
            versions = cached[pkg_name].to_a.compact.sort.reverse.map { |v|
              if v.strip.empty? || !v.match(VALID_EXACT_VERSION_PREFIX)
                Instrument.increment(
                  "etl.manifest_snapshot.parser.dependencies.warnings",
                  **tags_with_error("invalid_exact_version"))

                DependencyGraph.logger.warn("invalid exact version prefix",
                  "exception.message" => "invalid_exact_version",
                  "code.function" => "resolve_legacy_requires_ranges",
                  "gh.repo.id" => @hydro_message[:repository_id],
                  "gh.repo.owner_id" => @hydro_message[:owner_id],
                  "gh.repo.name_with_owner" => @hydro_message[:repository_nwo],
                  "gh.dependency_graph.manifest.filename" => @hydro_message[:manifest_file][:filename],
                  "gh.dependency_graph.manifest.path" => @hydro_message[:manifest_file][:path],
                  "gh.dependency_graph.package.name" => pkg_name,
                  "gh.dependency_graph.package.version" => v)

                next
              end

              reqs = ManifestAdapters::Npm::Requirements.new(v).normalize
              Versioning::RequirementSet.deserialize(reqs, allow_named_versions: false)
            }.select { |rset|
              !rset.nil? && rset.valid?
            }.compact

            cached[pkg_name] = versions
          end

          # iterate over all snapshot packages, resolving version ranges on
          # each package entry's "requires" clause to an exact version of
          # that dependency already captured in the snapshot
          resolved.each do |purl, entry|
            # temporarily cache this package's previously captured exact
            # version deps to avoid duplicates when resolving "requires"
            # range entries below
            entry_deps = {}
            entry[:dependencies].to_a.each { |purl|
              pkg_name = ns_and_name_from_purl(purl)
              entry_deps[pkg_name] = true
            }

            # resolve each "requires" entry on this snapshot package to an
            # exact version, and add it to the package's "dependencies"
            entry[:requires].to_h.each do |pkg_name, vspec|
              # if the "dependencies" list already resolved this package, skip this step
              next if entry_deps[pkg_name]

              # if the version range spec in the "requires" entry is invalid
              # (typo, non-semver spec etc.) we stat and skip it
              unless vspec.match(VALID_VERSION_PREFIX)
                Instrument.increment(
                  "etl.manifest_snapshot.parser.requires.warnings",
                  **tags_with_error("invalid_version_range"))

                DependencyGraph.logger.warn("invalid version range prefix",
                  "code.function" => "resolve_legacy_requires_ranges",
                  "gh.repo.id" => @hydro_message[:repository_id],
                  "gh.repo.owner_id" => @hydro_message[:owner_id],
                  "gh.repo.name_with_owner" => @hydro_message[:repository_nwo],
                  "gh.dependency_graph.manifest.filename" => @hydro_message[:manifest_file][:filename],
                  "gh.dependency_graph.manifest.path" => @hydro_message[:manifest_file][:path],
                  "gh.dependency_graph.package.name" => pkg_name,
                  "gh.dependency_graph.package.version" => vspec)

                next
              end

              # turn NPM styled version spec into DG's
              normalized = ManifestAdapters::Npm::Requirements.new(vspec).normalize
              target = Versioning::RequirementSet.deserialize(normalized, allow_named_versions: false)
              unless target.valid?
                Instrument.increment(
                  "etl.manifest_snapshot.parser.requires.warnings",
                  **tags_with_error("invalid_requirement_set"))
                next
              end

              # compare cached resolved versions found in the first parsing
              # pass to map each "requires" entry version spec to the right
              # exact package version on the snapshot
              cached[pkg_name].to_a.each do |candidate_version|
                # if candidate is a good match, capture it
                if target.contain?(candidate_version)
                  entry[:dependencies] << to_purl(pkg_name, candidate_version.exact_version)
                  break
                end
              end
            end
          end
        end
      end
    end
  end
end
