module Queries
  class RepositoryDependentsQuery
    include RelayQuery

    delegate :each, to: :results

    def initialize(owner_ids:, package_name:, version:, package_manager:, dependent_name:, limit: 25)
      @owner_ids = owner_ids
      @package_name = package_name
      @version = version
      @package_manager = package_manager
      @limit = limit
      @dependent_name = dependent_name

      @allows_named_versions = Types::PackageManager.allows_named_versions?(package_manager)
    end

    def results
      return @results if defined?(@results)
      results = scope
      results = results.where(NEXT_SLICE(), @after) if after?
      results = results.where(PREVIOUS_SLICE(), @before) if before?

      @results = before? ? results.last(limit) : results.first(limit)
    end

    def all_dependencies
      return @all_dependencies if defined?(@all_dependencies)

      if DependencyGraph.use_normalized_tables?
        @all_dependencies = query_all_dependencies_normalized
      else
        @all_dependencies = query_all_dependencies_denormalized
      end
    end

    def query_all_dependencies_normalized
      manifest_types = Types::Manifest.filter { |t| t.package_manager == package_manager }
      manifest_types -= Types::Manifest.superseded
      ManifestEntry
        .select("#{ManifestEntry.table_name}.*, #{Manifest.table_name}.name as dependent_package_name")
        .joins(manifest: :repository)
        .merge(Repository.where(github_owner_id: owner_ids))
        .where("#{Manifest.table_name}.manifest_type IN (?)", manifest_types.map(&:serialize))
        .where("#{ManifestEntry.table_name}.last_seen_at_revision = #{Manifest.table_name}.revision")
    end

    def query_all_dependencies_denormalized
      ManifestDependency
        .select("#{ManifestDependency.table_name}.*, #{Manifest.table_name}.name as dependent_package_name")
        .joins(manifest: :repository)
        .merge(Repository.where(github_owner_id: owner_ids))
        .merge(Manifest.not_superseded)
        .where("#{ManifestDependency.table_name}.package_name = ?", package_name)
        .where("#{Manifest.table_name}.package_manager = ?", package_manager.serialize)
        .where("#{ManifestDependency.table_name}.last_seen_at_revision = #{Manifest.table_name}.revision")
    end

    def package_release_base_scope
      @package_release_base_scope ||= PackageRelease.where(package_name: package_name, package_manager: package_manager)
    end

    def lower_version_count
      return @lower_version_count if defined?(@lower_version_count)

      # Following ordering rules defined in Versioning::Version
      lower_ids = if Versioning::GenericVersionParser.valid_named_version?(@allows_named_versions, version)
                    package_release_base_scope.select { |other_release| other_release.parsed_version < parsed_version }.pluck(:id)
                  else
                    requirement_set = Versioning::RequirementSet.deserialize("< #{version}", allow_named_versions: @allows_named_versions)
                    package_release_base_scope.matching_requirement_set(requirement_set).pluck(:id)
                  end

      @lower_version_count = lower_ids.in_groups_of(100, false).map do |lower_ids|
        Views::PackageReleaseDependentCount.where(github_owner_id: owner_ids, package_release_id: lower_ids).sum(:count)
      end.sum
    end

    def upper_version_count
      return @upper_version_count if defined?(@upper_version_count)

      upper_ids = if Versioning::GenericVersionParser.valid_named_version?(@allows_named_versions, version)
                    package_release_base_scope.select { |other_release| other_release.parsed_version > parsed_version }.pluck(:id)
                  else
                    requirement_set = Versioning::RequirementSet.deserialize("> #{version}", allow_named_versions: @allows_named_versions)
                    package_release_base_scope.matching_requirement_set(requirement_set).pluck(:id)
                  end

      @upper_version_count = upper_ids.in_groups_of(100, false).map do |upper_ids|
        Views::PackageReleaseDependentCount.where(github_owner_id: owner_ids, package_release_id: upper_ids).sum(:count)
      end.sum
    end

    def has_previous?
      return false unless results.first.present?

      scope.where(PREVIOUS_SLICE(), results.first).exists?
    end

    def has_next?
      return false unless results.last.present?

      scope.where(NEXT_SLICE(), results.last).exists?
    end

    def dependent_name?
      dependent_name.present?
    end

    private

    attr_reader :owner_ids, :package_name, :version, :package_manager, :dependent_name, :allows_named_versions

    def normalized_model_class
      DependencyGraph.use_normalized_tables? ? ManifestEntry : ManifestDependency
    end

    # TODO: Make these constants again when cleaning up normalization flags
    # rubocop:disable Naming/MethodName
    def NEXT_SLICE
      "#{normalized_model_class.table_name}.id < ?"
    end

    def PREVIOUS_SLICE
      "#{normalized_model_class.table_name}.id > ?"
    end
    # rubocop:enable Naming/MethodName

    def parsed_version
      @parsed_version ||= Versioning::VersionParser.parse(version, allow_named_versions: allows_named_versions)
    end

    def scope
      if DependencyGraph.use_normalized_tables?
        mpv = ManifestPackageVersion
          .joins(:manifest_package)
          .find_by(manifest_package: { package_manager: package_manager, package_name: package_name }, requirements: "= #{version}")
        if mpv.nil?
          # If no matching package version is found, return an empty scope
          @scope ||= all_dependencies.where("1 = 0")
        else
          @scope ||= all_dependencies.where(manifest_package_version_id: mpv.id).order(id: :desc)
        end
      else
        @scope ||= all_dependencies.where(requirements: "= #{version}").order(id: :desc)
      end

      if dependent_name?
        # Filter scope by repository dependent names if parameter is passed
        @scope = @scope.merge(Repository.where("nwo LIKE :substring", { substring: "%#{ActiveRecord::Base.sanitize_sql_like(dependent_name)}%" }))
      end

      @scope
    end
  end
end
