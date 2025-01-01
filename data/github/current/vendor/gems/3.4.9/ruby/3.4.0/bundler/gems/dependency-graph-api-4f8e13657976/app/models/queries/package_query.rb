module Queries
  class PackageQuery
    attr_reader :names, :package_manager, :ids, :limit, :debug, :sort_by, :repository_ids

    def initialize(options)
      @names = options[:names]
      @repository_ids = options[:repository_ids]
      @package_manager = options[:package_manager]
      @limit = options[:limit]
      @ids = options[:ids]
      @debug = options[:debug]
      @sort_by = options[:sort_by]&.upcase&.to_sym
    end

    def results
      scoped = Package.includes(:repository).references(:repository)
      scoped = scoped.limit(limit || 1000)
      scoped = scoped.with_name(names) if names?
      scoped = scoped.for_package_manager(package_manager) if package_manager?
      scoped = scoped.where(id: ids) if ids?

      if repository_ids?
        scoped = within_repo = scoped.for_repositories(repository_ids)

        non_debug_query = within_repo
                            .with_repository_id_certainty_of_at_least(minimum_repository_id_certainty)
                            .where(id: packages_with_corresponding_manifests)
                            .or(within_repo.with_repository_id_certainty_of_at_least(PackageToRepoMapping::Certainty::POSITIVE_MATCH))

        if debug?
          # Debug query has its own plans for for the non-debug-query -- We use it to lookup whether a package
          # will be considered associated to a repo and return extra debug info.
          debug_info = non_debug_query
        else
          scoped = non_debug_query
        end

      end

      case sort_by
      when :MOST_DEPENDENTS
        scoped.most_dependents_first
      when :ALPHABETICAL
        scoped.alphabetical
      when :MOST_CERTAIN_REPOSITORY_ID
        scoped.most_certain_repository_id_first
      else
        # :DEFAULT sort behavior, which finds a Package matching the repo name first and falls back to alphabetical.
        #
        # We start off with an alphabetical sort so we can return that if we don't have a direct package name match.
        scoped = scoped.order(Arel.sql(order_sql))

        if debug?
          PackageQueryDebugInfo.write_debug_info(scoped, debug_info, minimum_repository_id_certainty)
        end

        scoped
      end
    end

    def order_sql
      "CASE WHEN #{Package.table_name}.name = substring_index(#{Repository.table_name}.nwo, '/', -1) THEN 0 ELSE 1 END, lower(#{Package.table_name}.name) ASC"
    end

    def unmapped_packages
      unmapped_packages = Package.with_no_repository_mapping
      unmapped_packages = unmapped_packages.with_name(names) if names?
      unmapped_packages = unmapped_packages.for_package_manager(package_manager) if package_manager?

      unmapped_packages.most_dependents_first.limit(limit || 100)
    end

    private

    def ids?
      ids.present?
    end

    def repository_ids?
      repository_ids.present?
    end

    def names?
      names.present?
    end

    def package_manager?
      package_manager.present?
    end

    # Internal: Disable data quality filtering in favor of a more complete
    # results.
    def debug?
      debug.present?
    end

    def minimum_repository_id_certainty
      PackageToRepoMapping::Certainty.minimum_required_for_display
    end

    def packages_with_corresponding_manifests
      package_join = <<~SQL
        INNER JOIN #{Package.table_name} ON #{Package.table_name}.package_manager = #{Manifest.table_name}.package_manager
          AND #{Package.table_name}.name = #{Manifest.table_name}.name
      SQL

      Manifest
        .with_github_repository_id(repository_ids)
        .joins(package_join)
        .select("#{Package.table_name}.id")
    end
  end
end
