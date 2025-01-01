# frozen_string_literal: true

require "dependency_graph/tracing"

module Queries
  class VersionRangeDependentsQuery
    include RelayQuery
    include DependencyGraph::Tracing

    attr_reader :package_manager, :package_name, :requirements
    delegate :each, to: :dependents

    def initialize(package_manager:, package_name:, requirements:, limit: 100, after: nil, use_normalized_tables: false)
      @package_manager = package_manager
      @package_name = package_name
      @requirements = requirements
      @limit = limit
      @after = after
      @use_normalized_tables = use_normalized_tables
    end

    ##
    # Reset @dependencies when @after or @limit are set. This is because we memoize @dependencies
    # but .first() or .after() may be called after the query is made.
    # This is a dirty hack but it's how relay_query.rb which we are including works.

    def after(cursor)
      @dependencies = nil if cursor != @after
      super(cursor)
    end

    def first(n)
      @dependencies = nil if n != @limit
      super(n)
    end

    def get_log_context
      {
        graphql_query: :all_repositories_with_version_range,
        package_manager: package_manager,
        package_name: package_name,
        limit: limit,
        after: @after,
      }
    end

    def allow_named_versions?
      Types::PackageManager.allows_named_versions?(package_manager)
    end

    def requirement_set
      @requirement_set ||= Versioning::RequirementSet.deserialize(requirements, allow_named_versions: allow_named_versions?)
    end

    def valid?
      package_manager.present? &&
        package_name.present? &&
        requirement_set.valid?
    end

    trace_method :dependents
    def dependents
      return [] unless valid?

      @dependents ||=
        dependencies
          .without_superseded_in_repository
          .first(limit) # Drop the extra record fetched to peek at the next page
          .reject { |dependency| !dependency.current? || dependency.manifest_vendored? }
    end

    def has_next?
      dependencies.count > limit
    end

    def has_previous?
      @after.present?
    end

    # Return the last dependent that was in the range queried. This may be
    # a rejected dependent but it will always be the last one that was
    # in the fetched page more dependencies past the current page exist.
    def last_dependent
      dependencies.first(limit).last if has_next?
    end

    # Return a count of dependent manifests rather than dependent repos for now
    # because `count(distinct repository_id)` wasn't executing quickly enough.
    trace_method :estimated_dependent_repository_count
    def estimated_dependent_repository_count
      @estimated_dependent_repository_count ||=
        dependency_scope
          .optimizer_hints("MAX_EXECUTION_TIME(10000)")
          .count
    rescue ActiveRecord::StatementTimeout
      # We return -1 if this timeout occurs, and callers can infer that there is a reasonably
      # large amount of repositories in that case.
      -1
    end

    private

    trace_method :dependencies
    def dependencies
      return @dependencies if defined?(@dependencies) && !@dependencies.nil?

      ordered_scope = dependency_scope

      if @use_normalized_tables
        # Does NOT have a secondary order on manifest_entry.id in order to take advantage of the index on manifest_package_version.requirements
        ordered_scope = ordered_scope.order("`manifest_package_version`.`requirements`")
      else
        ordered_scope = ordered_scope.order(:requirements, :id)
      end

      @dependencies =
        ordered_scope
          .limit(limit + 1) # Fetch one extra record to peek at the next page
          .after(@after)
          .joins(:manifest)
          .eager_load(:manifest)
    end

    trace_method :normalized_manifest_package_id
    def normalized_manifest_package_id
      @normalized_manifest_package_id ||= ManifestPackage.where(package_manager: package_manager, package_name: package_name).pluck(:id).first
    end

    trace_method :dependency_scope
    def dependency_scope
      return @dependency_scope if defined?(@dependency_scope)

      if @use_normalized_tables
        @dependency_scope = ManifestEntry
          # Writing out full JOIN here so the resulting SQL can use `manifest_package_version` rather than the full table name
          .joins("INNER JOIN `#{ManifestPackageVersion.table_name}` `manifest_package_version` ON `manifest_package_version`.`id` = `#{ManifestEntry.table_name}`.`manifest_package_version_id`")
          .where("`manifest_package_version`.`manifest_package_id` = ?", normalized_manifest_package_id)
          .where("`manifest_package_version`.`requirements` IN (?)", vulnerable_requirements)
      else
        @dependency_scope =
          ManifestDependency
            .use_index("index_dg_manifest_dependencies_on_pkg_name_pkg_mgr_reqs")
            .for_package_manager(package_manager)
            .with_package_name(package_name)
            .where(requirements: vulnerable_requirements)
      end
    end

    trace_method :vulnerable_requirements
    def vulnerable_requirements
      return @vulnerable_requirements if defined? @vulnerable_requirements

      vulnerable_requirements = []

      all_package_requirements = nil
      if @use_normalized_tables
        all_package_requirements = ManifestPackageVersion
          .where(manifest_package_id: normalized_manifest_package_id)
          .pluck(:requirements)
      else
        # Get package requirements, being sure to pluck all three columns in the
        # database index even though we only need values for requirements. This
        # ensures MySQL optimizes the query using a "loose index scan."
        #
        # See: https://dev.mysql.com/doc/refman/5.7/en/group-by-optimization.html
        all_package_requirements = ManifestDependency
          .use_index("index_dg_manifest_dependencies_on_pkg_name_pkg_mgr_reqs")
          .for_package_manager(package_manager)
          .with_package_name(package_name)
          .distinct
          .pluck(:package_name, :package_manager, :requirements)
          .map { |(_package_name, _package_manager, requirements)| requirements }
      end

      all_package_requirements.each do |package_requirements|
        begin
          deserialized_package_requirements = Versioning::RequirementSet.deserialize(package_requirements, allow_named_versions: allow_named_versions?)

          next unless deserialized_package_requirements.valid?
          # We delegate the comparison of the requirement sets to Versioning::VulnerabilityComparator so we have a seam
          # to apply ecosystem-specific re-parsing of the requirement sets.
          #
          # This allows us to fix some cases where our default parsing/comparison rules does not align with ecosystem
          # conventions locally to vulnerability detection via the `is_contained` property in protobufs.
          #
          # See: https://github.com/github/dependency-graph/issues/5846
          vulnerability_comparator = Versioning::VulnerabilityComparator.new(
            vulnerable_requirements_set: requirement_set,
            subject_requirements_set: deserialized_package_requirements,
            package_manager: package_manager,
          )
          next unless vulnerability_comparator.vulnerable?

          vulnerable_requirements << package_requirements
        rescue StandardError => e
          # It might be a bit noisy to report all these potential exceptions based on untrusted user input to Sentry,
          # but since they are tagged here we can filter them out if it's a problem.
          Failbot.report(e,
            "gh.dependency_graph.query.name" => "VersionRangeDependentsQuery",
            "gh.dependency_graph.package_manager" => package_manager,
            "gh.dependency_graph.package_name" => package_name,
            "gh.dependency_graph.query.parameter.requirements" => requirements,
            "gh.dependency_graph.package_requirements" => package_requirements
          )
          next
        end
      end

      @vulnerable_requirements = vulnerable_requirements
    end
  end
end
