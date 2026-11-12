# frozen_string_literal: true

require_relative "../../lib/dependency_graph/connection"
require "dependency_graph/manifest_dependency_replicator"
require "dependency_graph/tracing"

module Ingest
  class ManifestLoader
    include DependencyGraph::Tracing

    attr_reader :generic_manifest

    INSTRUMENTATION_PREFIX = "etl.manifests".freeze

    def self.insert_repos
      @insert_repos ||= load_sql(:repos)
    end

    def self.insert_manifests
      @insert_manifests ||= load_sql(:manifests)
    end

    def self.insert_star_counts
      @star_counts ||= load_sql(:star_counts)
    end

    def self.load_sql(file)
      File.read(File.expand_path("../manifest_sql/#{file}.sql", __FILE__))
        .gsub("%manifests_table_name%", Manifest.table_name)
        .gsub("%repositories_table_name%", Repository.table_name)
        .gsub("%star_counts_table_name%", StarCount.table_name)
    end

    # Initializes a ManifestLoader for a given Manifest record retrieved from Kafka.
    # Use of normalized tables is disabled on GHES but enabled everywhere else.
    def initialize(generic_manifest)
      @generic_manifest = generic_manifest
      @manifest_dependency_replicator = DependencyGraph::ManifestDependencyReplicator.new

      @use_normalized_tables = DependencyGraph.use_normalized_tables?
    end

    # Processes a Manifest record and inserts it into the database.
    #
    # This is the body of the main loop of the "ManifestStage" ingestion task
    # as invoked by script/etl/ingest_manifests.
    trace_method :load
    def load
      db_manifest = nil

      instrument_timing("load.dist.time") do
        DependencyGraph.logger.log_and_failbot_context(context) do
          next if ignore_manifest?

          DependencyGraph::Connection.with_read_committed(role: :writing) do
            save_star_counts
            db_manifest = save_manifest
            remap_related_packages

            # We ingest Actions packages by loading dependencies from public manifests
            load_actions_packages if public_actions_manifest? && !DependencyGraphAPI.enterprise?
          end
        rescue => e
          Instrument.increment("#{INSTRUMENTATION_PREFIX}.load.error",
                                package_manager: generic_manifest.package_manager || "unknown",
                                error: e.class.to_s
          )

          # Only send errors to Failbot if they aren't retryable
          if RetryJob::RETRYABLE_ERRORS.include?(e.class)
            raise e
          else
            Failbot.report(e)
          end
        end
      end

      return db_manifest
    end

    def ignore_manifest?
      manifest.invalid? || manifest.unsupported_vendored_manifest? || Blocklist.blocklisted_manifest?(generic_manifest) || generic_manifest.malformed?
    end

    # Internal: Find an existing repository record if one exists for the
    #   manifest. Otherwise, create a repository record for the manifest.
    #
    # Returns an Integer representing the repository ID.
    trace_method :find_or_create_repository
    def find_or_create_repository
      repository = ActiveRecord::Base.connected_to(role: :reading) do
        Repository.find_by(
          github_repository_id: generic_manifest.github_repository_id,
          github_owner_id: generic_manifest.github_owner_id,
          nwo: generic_manifest.repository_nwo,
          public: !generic_manifest.private_repository?,
        )
      end

      return repository.id if repository.present?

      insert(self.class.insert_repos, {
        github_repository_id: generic_manifest.github_repository_id,
        github_owner_id: generic_manifest.github_owner_id,
        nwo: generic_manifest.repository_nwo,
        visibility_public: !generic_manifest.private_repository?,
      })
    end

    trace_method :save_star_counts
    def save_star_counts
      return if generic_manifest.repository_stargazer_count.nil?
      return if generic_manifest.repository_stargazer_count == 0

      instrument_timing("save_star_counts") do
        return if ActiveRecord::Base.connected_to(role: :reading) do
          StarCount.exists?(
            github_repository_id: generic_manifest.github_repository_id,
            star_count: generic_manifest.repository_stargazer_count
          )
        end

        insert(self.class.insert_star_counts, {
          github_repository_id: generic_manifest.github_repository_id,
          star_count: generic_manifest.repository_stargazer_count
        })
      end
    end

    def dependencies_for_revision(manifest_id:, revision:)
      if use_normalized_tables
        ManifestEntry
          .includes(manifest_package_version: :manifest_package)
          .where(manifest_id: manifest_id, last_seen_at_revision: revision)
          .load
      else
        ManifestDependency
          .where(manifest_id: manifest_id, last_seen_at_revision: revision)
          .select(:package_manager, :package_name, :requirements)
          .load
      end
    end

    trace_method :save_manifest
    def save_manifest
      # Determine if we should run calls to update Dependency Insights. In addition to checking the DB,
      # make sure that this manifest isn't superseded (DepInsights only cares about lockfiles).
      should_update_dependency_insights = Types::Manifest.superseded.exclude?(generic_manifest.manifest_type) \
        && DependencyInsightsBackfill.exists?(github_owner_id: generic_manifest.github_owner_id)

      repository_id = find_or_create_repository

      manifest_id = insert_manifest(repository_id: repository_id)
      manifest = Manifest.select(:id, :revision).find(manifest_id)

      insert_missing_abstract_repository_dependencies(repository_id: repository_id)

      dependencies_in_last_revision = nil
      ActiveRecord::Base.connected_to(role: :reading) do
        dependencies_in_last_revision = dependencies_for_revision(manifest_id: manifest.id, revision: manifest.revision - 1)
      end

      insert_manifest_dependencies(manifest)

      dependencies_in_this_revision = dependencies_for_revision(manifest_id: manifest.id, revision: manifest.revision)

      if should_update_dependency_insights
        instrument_timing("update_package_release_dependent_counts") do
          PackageReleaseDependentCountUpdater.run!(
            github_owner_id: generic_manifest.github_owner_id,
            dependencies_in_last_revision: dependencies_in_last_revision,
            dependencies_in_this_revision: dependencies_in_this_revision,
          )
        end
      end

      manifest
    end

    trace_method :insert_manifest
    def insert_manifest(repository_id:)
      insert(self.class.insert_manifests, {
        package_manager: manifest.package_manager.serialize,
        manifest_type:   manifest.manifest_type.serialize,
        filename:        manifest.filename,
        path:            manifest.path,
        name:            manifest.name,
        latest_git_ref:  manifest.latest_git_ref,
        last_pushed_at:  manifest.last_pushed_at,
        repository_id:   repository_id,
      })
    end

    trace_method :insert_manifest_dependencies
    def insert_manifest_dependencies(manifest)
      Instrument.increment("#{INSTRUMENTATION_PREFIX}.manifest_dependency.import_total")

      # tool for deduplicating dependencies without .sort.uniq (the previous method)
      pkg_names = Set.new
      manifest_dependencies = []

      generic_manifest.dependencies.each do |dependency|
        next if pkg_names.include?(dependency.package_name)
        dep = build_dependency(manifest, dependency)
        next if dep.nil?
        manifest_dependencies << dep
      end

      # stat counts of dependencies per manifest, tagged by Package manager type
      # TODO: it would be nice if all these metric keys and action names matched up :(
      deps_count = manifest_dependencies&.count || 0
      Instrument.count("#{INSTRUMENTATION_PREFIX}.manifest_dependency.total_deps_submitted",
                        deps_count, package_manager: manifest.package_manager || "unknown")

      instrument_timing("manifest_dependency.import_insert_duration") do
        manifest_dependencies.each_slice(10) do |slice|
          if write_to_manifest_dependencies?
            ManifestDependency.import(slice,
              # Excluding `created_at` because otherwise activerecord-import will set it to Time.now, which is misleading
              # and caused issues with `PackageReleaseDependentCountUpdater`, c.f. https://github.com/github/dependency-graph-api/pull/2873.
              on_duplicate_key_update: ManifestDependency.column_names.map(&:to_sym).excluding([:id, :created_at])
            )
          end

          if write_to_manifest_entries?
            manifest_dependency_replicator.to_manifest_entries(slice)
          end
        end
      end
    end

    def parse_requirements(requirements)
      Versioning::RequirementSet.deserialize(requirements,
        on_error: -> (invalid) {
          Instrument.increment("etl.invalid_requirements",
                               invalid_range: invalid,
                               context: { stage: :manifest_ingest }
          )
        },
        allow_named_versions: Types::PackageManager.allows_named_versions?(generic_manifest.package_manager),
      )
    end

    def build_dependency(manifest, dependency)
      requirements = parse_requirements(dependency.requirements)

      return unless requirements.valid?

      package_name = package_manager == Types::PackageManager[:pip] ? normalize_package_name(dependency.package_name) : dependency.package_name

      record = ManifestDependency.new(
        scope:                 dependency.scope.serialize,
        package_manager:       package_manager,
        package_name:          package_name,
        requirements:          requirements.serialize,
        raw_requirements:      dependency.raw_requirements,
        encoded_lower_bound:   requirements.encoded_lower_bound,
        encoded_upper_bound:   requirements.encoded_upper_bound,
        manifest:              manifest,
        last_seen_at_revision: manifest.revision,
      )

      if record.invalid?
        Instrument.increment("etl.invalid_dependency",
                             depedency: dependency,
                             context: {
                               stage: :manifest_ingest,
                             })

        return
      end

      record
    end

    def insert(sql, values)
      ActiveRecord::Base.connected_to(role: :writing) do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          sql = ActiveRecord::Base.send(:sanitize_sql_array, [sql, values])
          connection.insert(sql)
        end
      end
    end

    def remap_related_packages
      instrument_timing("remap_related_packages") do
        packages = Package
          .where(package_manager: generic_manifest.package_manager,
                 name: generic_manifest.dependent_name)
          .or(Package.for_repositories(generic_manifest.github_repository_id))
        packages.each do |package|
          PackageToRepoMapping::Matcher.process(package)
        end
      end
    end

    def public_actions_manifest?
      package_manager == Types::PackageManager[:actions] && !generic_manifest.private_repository?
    end

    def load_actions_packages
      packages = generic_manifest.dependencies.map do |dep|
        version = dep.requirements.split.last
        { name: dep.package_name, version: version }
      end

      Rails.env.development? ? ActionsPackageJob.perform_now(packages) : ActionsPackageJob.perform_later(packages)
    end

    trace_method :insert_missing_abstract_repository_dependencies
    def insert_missing_abstract_repository_dependencies(repository_id:)
      Instrument.increment("#{INSTRUMENTATION_PREFIX}.abstract_repository_dependency.import_total")

      existing_dependencies = nil
      ActiveRecord::Base.connected_to(role: :reading) do
        existing_dependencies = AbstractRepositoryDependency.where(repository_id: repository_id, package_manager: generic_manifest.package_manager).pluck(:package_name)
      end

      manifest_dependencies = generic_manifest.dependencies.collect(&:package_name).uniq
      missing_dependencies = manifest_dependencies - existing_dependencies
      missing_abstract_repo_dependencies = missing_dependencies.sort.map do |package_name|
        [repository_id, generic_manifest.package_manager.serialize, package_name]
      end

      missing_abstract_repo_dependencies.each_slice(10) do |slice|
        AbstractRepositoryDependency.import(
          [:repository_id, :package_manager, :package_name],
          slice,
          on_duplicate_key_ignore: true
        )
      end
    end

    def context
      {
        "gh.dependency_graph.package_manager" => generic_manifest.package_manager,
        "gh.dependency_graph.manifest.type" => generic_manifest.manifest_type,
        "gh.dependency_graph.manifest.filename" => generic_manifest.filename,
        "gh.dependency_graph.manifest.name" => generic_manifest.dependent_name,
        "gh.repo.id" => generic_manifest.github_repository_id,
      }
    end

    def manifest
      return @manifest if defined?(@manifest)

      normalized_path = generic_manifest.path.to_s.strip.sub(/\A\//, "")

      @manifest ||= ::Manifest.new({
        package_manager: generic_manifest.package_manager,
        manifest_type:   generic_manifest.manifest_type,
        filename:        generic_manifest.filename,
        path:            normalized_path,
        name:            generic_manifest.dependent_name,
        latest_git_ref:  generic_manifest.git_ref,
        last_pushed_at:  generic_manifest.pushed_at,
      })
    end

    def instrument_timing(name, &block)
      instrumentation_name = "#{INSTRUMENTATION_PREFIX}.#{name}"
      GitHub::Telemetry.tracer.in_span(instrumentation_name) do
        Instrument.time_dist(instrumentation_name, package_manager: context["gh.dependency_graph.package_manager"], &block)
      end
    end

    private

    attr_reader :manifest_dependency_replicator, :use_normalized_tables

    def package_manager
      @package_manager = Types::PackageManager.coerce(generic_manifest.package_manager)
    end

    def normalize_package_name(name)
      ManifestAdapters::Pip::DependencyString.normalize_package_name(name)
    end

    def write_to_manifest_dependencies?
      !use_normalized_tables
    end

    def write_to_manifest_entries?
      use_normalized_tables
    end
  end
end
