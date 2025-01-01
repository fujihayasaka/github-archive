# frozen_string_literal: true
require_relative "../../lib/dependency_graph/connection"
require_relative "../../lib/repository_finder"
require "dependency_graph/tracing"
require_relative "clearlydefined"

# Public: Maps entities from the PackageRelease pipeline to packages
# and package versions.
module Ingest
  class PackageLoader
    include RepositoryFinder
    include DependencyGraph::Tracing

    INSTRUMENTATION_PREFIX = "etl.packages".freeze
    AUTHORITATIVE_PACKAGE_MANAGERS = [
      Types::PackageManager[:go],
      Types::PackageManager[:actions],
      Types::PackageManager[:rust],
      Types::PackageManager[:composer],
      Types::PackageManager[:pub],
      Types::PackageManager[:npm],
      Types::PackageManager[:maven],
    ]

    def self.insert_packages
      @insert_packages ||= load_sql(:packages)
    end

    def self.insert_package_releases
      @insert_package_releases ||= load_sql(:package_releases)
    end

    def self.load_sql(file)
      File.read(File.expand_path("../package_sql/#{file}.sql", __FILE__))
        .gsub("%packages_table_name%", Package.table_name)
        .gsub("%package_versions_table_name%", PackageRelease.table_name)
    end

    # Initializes a PackageLoader for a given PackageRelease record retrieved from Kafka.
    def initialize(release)
      @release = release
      @cd_config = Clearlydefined::Config.new
      @harvester = Clearlydefined::Harvester.new(@cd_config)
    end

    # Processes a PackageRelease record and inserts it into the the database.
    #
    # This is the body of the main loop of the "PackageStage" ingestion task
    # as invoked by script/etl/ingest_packages.

    trace_method :load, span_attribute_extractor: -> (instance, *_args, **_kwargs) { instance.span_tags }
    def load
      DependencyGraph.logger.info("loading package",
        "gh.job.name" => "package_loader",
        "gh.dependency_graph.package.name" => release.package_name,
        "gh.dependency_graph.package_manager" => release.package_manager.to_s,
        "gh.dependency_graph.package.version" => release.version,
      )

      return unless release.package_name.present?

      # Skip processing this release if we're blocklisting the package
      return if Blocklist.blocklisted_package?(release)

      Instrument.time_dist("etl.packages.load.dist.time", package_manager: release.package_manager) do
        load_package(release)
      end
    end

    def span_tags
      {
        "gh.dependency_graph.package_manager" => release.package_manager.to_s
      }
    end

    private

    attr_reader :release

    trace_method :load_package, span_attribute_extractor: -> (instance, *_args, **_kwargs) { instance.span_tags }
    def load_package(release)
      package_id, release_id = []

      instrument_timing("load_package") do
        DependencyGraph::Connection.with_read_committed(role: :writing) do
          package_id, release_id, created_new_release = insert_package_and_release(release)
          if created_new_release
            insert_missing_abstract_package_dependencies(release, package_id)
            insert_package_dependencies(release, release_id)
          end
        end
      end
    end

    trace_method :insert_package_and_release, span_attribute_extractor: -> (instance, *_args, **_kwargs) { instance.span_tags }
    def insert_package_and_release(release)
      instrument_timing("insert_package_and_release") do
        repo = lookup_repo(release)

        package_label, package_name = normalize_package_name(release.package_manager, release.package_name)

        package_id = insert(self.class.insert_packages, {
          package_manager:         release.package_manager.serialize,
          package_name:            package_name,
          package_label:           package_label,
          last_published_at:       encode_datetime(release.published_at)
        })

        package = Package.find(package_id)

        # NOTE: We will likely try to drop repository{_nwo, _id, _id_certainity} from
        # releases soon, considering we don't use release specific metadata in our product and instead use
        # the Package data. See https://github.com/github/dependency-graph/issues/1259 for details.

        # The logic implemented here preserves historical behaviour of repository mapping for releases.
        # See https://github.com/github/dependency-graph-api/pull/2818 for details.
        # For private repositories we do not store the repository_id, but we assign the mapping `Certainty::UNVERIFIED`
        # to reflect that the package registry does point to a repository but we chose not to store it (as opposed to not
        # having the information at all).
        release_repo_id = nil
        release_repo_id_certainty = PackageToRepoMapping::Certainty::NULL
        if repo.present?
          if repo.public?
            release_repo_id = repo.github_repository_id
          else
            release_repo_id = nil
          end

          # apply release override if package manager (registry source) is authoritative
          # unless the parent package has previously been overridden directly (chatop repair etc.)
          if AUTHORITATIVE_PACKAGE_MANAGERS.include?(release.package_manager) &&
              package.repository_id_certainty <= PackageToRepoMapping::Certainty::POSITIVE_MATCH
            release_repo_id_certainty = PackageToRepoMapping::Certainty::POSITIVE_MATCH
          else
            release_repo_id_certainty = PackageToRepoMapping::Certainty::UNVERIFIED
          end
        end

        release_id, release_license, release_url, release_unpublished_at = ActiveRecord::Base.connected_to(role: :reading) do
          PackageRelease.where(package_id: package_id, name: release.version).pluck(:id, :license, :source_url, :unpublished_at).first
        rescue ActiveRecord::ActiveRecordError => e
          DependencyGraph.logger.error("Error checking for existing release", e)
          [nil, nil, nil, nil]
        end

        # If there is no preexisting release ID, then we know we're creating a new one.
        created_new_release = release_id.nil?

        Instrument.increment("etl.packages.load.insert.release",
          package_manager: release.package_manager.to_s,
          create_release: created_new_release,
          updated_license: release_license != release.license,
          updated_source_url: release_url != release.source_url,
          updated_unpublished_at: release_unpublished_at != encode_datetime(release.unpublished_at)
        )

        # We also might want to _update_ the release if the license or source URL has changed.
        if release_id.nil? || (release_license != release.license) || (release_url != release.source_url) || (release_unpublished_at != encode_datetime(release.unpublished_at))
          release_id = insert(self.class.insert_package_releases, {
            package_id:              package_id,
            package_manager:         release.package_manager.serialize,
            package_name:            package_name,
            version:                 release.version,
            encoded:                 encode_version(release.version),
            published_at:            encode_datetime(release.published_at),
            unpublished_at:          encode_datetime(release.unpublished_at),
            repository_id:           release_repo_id,
            repository_id_certainty: release_repo_id_certainty,
            license:                 release.license, # only applied if license present
            source_url:              release.source_url.presence
          })
        end

        if AUTHORITATIVE_PACKAGE_MANAGERS.include?(release.package_manager)
          # This implements the behaviour described in https://github.com/github/dependency-graph/issues/1314. For
          # registries that are "authoritative" we set the repository mapping with high-certainty (POSITIVE_MATCH) based
          # on the release event.
          #
          # Historically we haven't been storing mappings for private GitHub repositories, and
          # we preserve that behaviour here. In that case, we assign POSITIVE_MATCH certainty to the nil mapping so that
          # it is not overriden by heuristics (we know the authoritative repo but we chose not to store it because it's private,
          # so we don't want heuristics to guess another repo).
          #
          # If the release event doesn't map to a GitHub repository, we preserve the historical behaviour of falling back on heuristics.
          if package.repository_id_certainty <= PackageToRepoMapping::Certainty::POSITIVE_MATCH
            if repo.present?
              if repo.public?
                package.update!(repository_id: repo.github_repository_id, repository_id_certainty: PackageToRepoMapping::Certainty::POSITIVE_MATCH)
              else
                package.update!(repository_id: nil, repository_id_certainty: PackageToRepoMapping::Certainty::POSITIVE_MATCH)
              end
            else
              # If the release has no repository information we reset the mapping and then fallback on heuristics.
              package.update!(repository_id: nil, repository_id_certainty: PackageToRepoMapping::Certainty::NULL)
              PackageToRepoMapping::Matcher.process(package)
            end
          else
            # If the package is already mapped with certainty > POSITIVE_MATCH (e.g. manually mapped with `Certainty::OVERRIDE`), we do nothing.
          end
        else
          # If the repository extracted from this release event has higher certainty than what we currently have, then
          # we update the package. We then run heuristics to give them a chance to match with even higher certainty.
          if package.repository_id_certainty <= release_repo_id_certainty
            package.update!(repository_id: release_repo_id, repository_id_certainty: release_repo_id_certainty)
          end
          PackageToRepoMapping::Matcher.process(package)
        end

        # Send packages with missing license to ClearlyDefined harvester.

        # DG doesn't accept licenses from CD when they have a license in place already.
        # TODO: if the above changes, this condition should be revisited.
        if release.license.blank? && @cd_config.harvester_enabled
          Instrument.increment("etl.packages.load.missing_license",
            package_manager: release.package_manager.to_s
          )
          package_with_version = release.package_name + "/" + release.version
          Instrument.time_dist("etl.packages.load.harvester_call") do
            unless @harvester.harvest(release.package_manager, package_with_version)
              Instrument.increment("etl.packages.load.harvester_error",
                package_manager: release.package_manager.to_s
              )
            end
          end
        end
        [package_id, release_id, created_new_release]
      end
    end

    trace_method :insert_missing_abstract_package_dependencies, span_attribute_extractor: -> (instance, *_args, **_kwargs) { instance.span_tags }
    def insert_missing_abstract_package_dependencies(release, package_id)
      instrument_timing("insert_missing_abstract_package_dependencies") do
        existing_dependencies = AbstractPackageDependency.where(dependent_id: package_id, package_manager: release.package_manager).pluck(:package_name)
        package_dependencies = release.dependencies.collect(&:package_name).uniq
        missing_dependencies = package_dependencies - existing_dependencies
        missing_abstract_package_dependencies = missing_dependencies.sort.map { |package_name|
          AbstractPackageDependency.new({
            dependent_id:    package_id,
            package_manager: release.package_manager.serialize,
            package_name:    package_name,
          })
        }

        missing_abstract_package_dependencies.each_slice(10) do |slice|
          AbstractPackageDependency.import(slice, on_duplicate_key_ignore: true)
        end
      end
    end

    trace_method :insert_package_dependencies, span_attribute_extractor: -> (instance, *_args, **_kwargs) { instance.span_tags }
    def insert_package_dependencies(release, release_id)
      instrument_timing("insert_package_dependencies") do
        release_dependencies = release.dependencies.sort_by(&:package_name)
        release_dependencies.each_slice(10) do |slice|
          PackageDependency.import(slice.map { |dependency|
            build_dependency(release_id, release, dependency)
          }.compact, validate: false, on_duplicate_key_update: [
            :package_manager,
            :scope,
            :requirements,
            :encoded_lower_bound,
            :encoded_upper_bound,
            :package_name,
            :package_label,
            :dependent_id
          ])
        end
      end
    end

    def build_dependency(release_id, release, dependency)
      return unless dependency.package_name.present?

      requirements = parse_requirements(release, dependency.requirements)
      package_label, package_name = normalize_package_name(release.package_manager, dependency.package_name)
      record = PackageDependency.new({
        dependent_id:        release_id,
        package_manager:     release.package_manager.serialize,
        package_name:        package_name,
        package_label:       package_label,
        requirements:        requirements.serialize,
        encoded_lower_bound: requirements.encoded_lower_bound,
        encoded_upper_bound: requirements.encoded_upper_bound,
        scope:               dependency.scope.serialize,
      })

      if record.invalid?
        Instrument.increment("etl.invalid_dependency",
          dependency: dependency,
          context: {
            stage: :package_ingest,
          })

        return
      end

      record
    end

    # Normalizes the package name only if the package manager
    # needs to apply such normalization
    #
    # It returns the [package label, package_name]
    # package_label will be nil if equal to name
    def normalize_package_name(package_manager, name)
      if Types::PackageManager[:pip] == package_manager
        [name, ManifestAdapters::Pip::DependencyString.normalize_package_name(name)]
      else
        [nil, name]
      end
    end

    trace_method :lookup_repo, span_attribute_extractor: -> (instance, *_args, **_kwargs) { instance.span_tags }
    def lookup_repo(release)
      url = [release.source_url, release.home_url].map { |u| GitHubUrl.new(u) }.find(&:valid?)
      if url && url.valid?
        nwo = "#{url.owner}/#{url.name}"
        return find_repo(nwo: nwo)
      end
    end

    def parse_requirements(release, requirements)
      Versioning::RequirementSet.deserialize(requirements,
        on_error: -> (invalid) {
          Instrument.increment("etl.invalid_requirements",
            context: {
              stage:           :package_ingest,
            }
          )
        },
        allow_named_versions: Types::PackageManager.allows_named_versions?(release.package_manager),
      )
    end

    def encode_datetime(datetime)
      return nil unless datetime.present?

      # If 0 is passed as a datetime it is invalid, given that we'll never have packages published at 1970-01-01
      return nil if datetime.to_i.zero?

      Time.zone.at(datetime).strftime("%F %T")
    end

    def encode_version(version)
      Versioning::VersionParser.parse(version, allow_named_versions: Types::PackageManager.allows_named_versions?(release.package_manager)).encoded.to_i
    rescue Versioning::NoEncodedVersionError
      nil
    end

    def insert(sql, values)
      ActiveRecord::Base.connected_to(role: :writing) do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          sql = ActiveRecord::Base.send(:sanitize_sql_array, [sql, values])
          connection.insert(sql)
        end
      end
    end

    def instrument_timing(name, &block)
      instrumentation_name = "#{INSTRUMENTATION_PREFIX}.#{name}.dist.time"
      package_manager = release.package_manager.to_s
      Instrument.time_dist(instrumentation_name, package_manager: package_manager, &block)
    end
  end
end
