require_relative "../../../lib/dependency_graph/object_model/base_graphql_manifest"

module Queries
  class DependenciesQuery
    def initialize(dependent:, limit: 250, prefer: nil)
      @dependent = dependent
      @limit     = limit
      @prefer    = prefer
    end

    def dependencies
      if dependent.is_a? DependencyGraph::ObjectModel::BaseGraphqlManifest
        if @prefer.present?
          preferred_set = @prefer.to_set
          dependent.dependencies.sort_by { |dep| [preferred_set.include?(dep.package_name) ? 0 : 1, dep.package_name] }
        else
          dependent.dependencies.sort_by(&:package_name)
        end
      else
        dependency_scope
          .order(Arel.sql(order_sql))
          .select(select_sql)
          .then do |s|
          if Types::PackageManager.no_sub_dependencies?(package_manager)
            s.select("false as has_dependencies")
          else
            s.select("(#{has_dependencies_package_versions_id.to_sql}) as package_versions_id")
              .select("(#{has_dependencies_subquery}) as has_dependencies")
          end
        end
          .joins("LEFT OUTER JOIN #{Package.table_name} ON " +
                 "#{Package.table_name}.name = #{dependency_package_table}.package_name AND " +
                 "#{Package.table_name}.package_manager = #{dependency_package_table}.package_manager")
          .select("#{Package.table_name}.repository_id AS package_github_repository_id")
          .select("#{Package.table_name}.repository_id_certainty AS package_github_repository_id_certainty")
          .select("#{Package.table_name}.id as package_id")
          .joins("LEFT JOIN #{PackageRelease.table_name} ON " +
                 # Join when the requirements are an exact version by matching on beginning with = and having no commas
                 "#{PackageRelease.table_name}.name = IF(#{dependency_requirements_table}.requirements REGEXP '^=[^,]+$', REPLACE(#{dependency_requirements_table}.requirements, '= ', ''), NULL) AND " +
                 "#{PackageRelease.table_name}.package_name = #{dependency_package_table}.package_name AND " +
                 "#{PackageRelease.table_name}.package_manager = #{dependency_package_table}.package_manager")
          .select("#{PackageRelease.table_name}.license as license")
      end
    end

    def dependencies_count
      dependency_scope.count
    end

    private

    def select_sql
      if use_normalized_tables?
        "#{dependencies_table}.*, #{dependency_package_table}.*, #{dependency_requirements_table}.*"
      else
        "#{dependencies_table}.*"
      end
    end

    def order_sql
      if @prefer.present?
        "CASE WHEN #{dependency_package_table}.package_name IN (#{prefer_sql}) THEN 0 ELSE 1 END, #{dependency_package_table}.package_name ASC"
      else
        "#{dependency_package_table}.package_name ASC"
      end
    end

    def prefer_sql
      @prefer.map { |package_name| "'#{ActiveRecord::Base.sanitize_sql(package_name)}'" }.join(",")
    end

    def has_dependencies_package_versions_id
      Package.for_package_manager(package_manager)
        .select("MAX(#{PackageRelease.table_name}.id)")
        .joins("JOIN #{PackageRelease.table_name} ON #{PackageRelease.table_name}.package_id = #{Package.table_name}.id")
        .where("#{Package.table_name}.name = #{dependency_package_table}.package_name")
        .where("#{PackageRelease.table_name}.encoded BETWEEN #{dependency_requirements_table}.encoded_lower_bound AND #{dependency_requirements_table}.encoded_upper_bound")
    end

    def has_dependencies_subquery
      "SELECT EXISTS (SELECT 1 FROM #{PackageDependency.table_name} specs WHERE specs.dependent_id = package_versions_id LIMIT 1)"
    end

    def dependencies_table
      dependency_scope.table_name
    end

    def package_manager
      dependent.package_manager
    end

    def dependency_package_table
      if use_normalized_tables?
        ManifestPackage.table_name
      else
        dependency_scope.table_name
      end
    end

    def dependency_requirements_table
      if use_normalized_tables?
        ManifestPackageVersion.table_name
      else
        dependency_scope.table_name
      end

    end

    def dependency_scope
      return @dependency_scope if defined?(@dependency_scope)

      if use_normalized_tables?
        scope = dependent.entries.includes(manifest_package_version: [:manifest_package]).references(:manifest_package_versions, :manifest_packages)
      else
        scope = dependent.dependencies
      end

      if dependent.has_revisions?
        scope = scope.as_of_revision(dependent.revision)
      end

      @dependency_scope = scope
    end

    def use_normalized_tables?
      return @use_normalized_tables if defined?(@use_normalized_tables)

      @use_normalized_tables = dependent.is_a?(Manifest) && DependencyGraph.use_normalized_tables?
    end

    attr_reader :dependent
  end
end
