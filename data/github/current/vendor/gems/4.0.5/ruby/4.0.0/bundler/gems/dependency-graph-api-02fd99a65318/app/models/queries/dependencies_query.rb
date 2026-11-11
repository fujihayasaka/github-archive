require_relative "../../../lib/dependency_graph/object_model/base_graphql_manifest"
require_relative "../../../lib/dependency_graph/object_model/ds_graphql_dependency"
require_relative "../../../lib/dependency_graph/object_model/dgp_graphql_dependency"
require "base64"
require "digest/sha2"

module Queries
  class DependenciesQuery
    CACHE_KEY_PREFIX = "dependencies_query"
    DEFAULT_CACHE_TTL_SECONDS = 600 # 10 minutes

    def initialize(dependent:, limit: 250, prefer: nil)
      @dependent = dependent
      @limit     = limit
      @prefer    = prefer
    end

    def dependencies
      if dependent.is_a? DependencyGraph::ObjectModel::BaseGraphqlManifest
        deps = fetch_graphql_manifest_dependencies
        if @prefer.present?
          preferred_set = @prefer.to_set
          deps.sort_by { |dep| [preferred_set.include?(dep.package_name) ? 0 : 1, dep.package_name] }
        else
          deps.sort_by(&:package_name)
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
    rescue ActiveRecord::StatementTimeout
      Instrument.increment("query.statement_timeout", query_site: "dependencies_query.dependencies")
      raise GraphQL::ExecutionError, "Query exceeded maximum execution time"
    end

    def dependencies_count
      if dependent.is_a? DependencyGraph::ObjectModel::BaseGraphqlManifest
        fetch_graphql_manifest_dependencies.count
      else
        dependency_scope.count
      end
    rescue ActiveRecord::StatementTimeout
      Instrument.increment("query.statement_timeout", query_site: "dependencies_query.dependencies_count")
      -1
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

      @dependency_scope = scope.optimizer_hints("MAX_EXECUTION_TIME(#{DependencyGraph::Application::MAX_QUERY_EXECUTION_TIME_MS})")
    end

    def use_normalized_tables?
      return @use_normalized_tables if defined?(@use_normalized_tables)

      @use_normalized_tables = dependent.is_a?(Manifest) && DependencyGraph.use_normalized_tables?
    end

    attr_reader :dependent

    def fetch_graphql_manifest_dependencies
      if dependencies_cache_enabled?
        cache_hit = true
        cached_deps = Rails.cache.fetch(dependencies_cache_key, expires_in: dependencies_cache_ttl) do
          cache_hit = false
          serialize_dependencies_for_cache(dependent.dependencies).tap do |serialized|
            Instrument.distribution("dependencies_query.cache.write.dependencies_count", serialized.size)
          end
        end

        begin
          result = deserialize_cached_dependencies(cached_deps)
        rescue TypeError, KeyError, Google::Protobuf::ParseError => e
          DependencyGraph.logger.warn("Dependencies query cache deserialization failed; rebuilding cache entry",
                                      "exception.class" => e.class.name,
                                      "exception.message" => e.message[..500])
          Instrument.increment("dependencies_query.cache.serialization_error")
          Rails.cache.delete(dependencies_cache_key)
          cache_hit = false
          result = dependent.dependencies
        end
        Instrument.increment(cache_hit ? "dependencies_query.cache.hit" : "dependencies_query.cache.miss")
        result
      else
        dependent.dependencies
      end
    end

    def dependencies_cache_enabled?
      return false unless dependent.respond_to?(:github_repository_id)

      repository_id = dependent.github_repository_id
      return false if repository_id.blank?

      repo_actor = FeatureFlags::Actor::Repository.new(repository_id)
      DependencyGraph.flipper[:dependency_graph_graphql_manifest_cache].enabled?(repo_actor)
    end

    def dependencies_cache_ttl
      DEFAULT_CACHE_TTL_SECONDS.seconds
    end

    def dependencies_cache_key
      key_data = {
        r: dependent.github_repository_id,
        m: dependent.id,
        t: dependent.class.name,
      }
      # consistent with https://github.com/github/github/blob/cd71ffd728da3a37f8c5eb8c55e06404815c71b6/app/platform/instrumentation/tracking_hash.rb#L11
      bytes = Digest::SHA256.digest(key_data.to_json)
      digest = Base64.urlsafe_encode64(bytes)
      "#{CACHE_KEY_PREFIX}/#{digest}"
    end

    def serialize_dependencies_for_cache(deps)
      deps.map do |dep|
        if dep.respond_to?(:cache_payload)
          dep.cache_payload
        else
          { source: "direct", dependency: dep }
        end
      end
    end

    def deserialize_cached_dependencies(cached_deps)
      return cached_deps if cached_deps.blank? || !cached_deps.first.is_a?(Hash)

      cached_deps.map do |entry|
        case entry[:source]
        when "snapshots"
          DependencyGraph::ObjectModel::DSGraphqlDependency.from_cache_payload(entry)
        when "dgp"
          DependencyGraph::ObjectModel::DGPGraphqlDependency.from_cache_payload(entry)
        when "direct"
          entry.fetch(:dependency)
        else
          raise TypeError, "Unsupported dependency cache source: #{entry[:source]}"
        end
      end
    end
  end
end
