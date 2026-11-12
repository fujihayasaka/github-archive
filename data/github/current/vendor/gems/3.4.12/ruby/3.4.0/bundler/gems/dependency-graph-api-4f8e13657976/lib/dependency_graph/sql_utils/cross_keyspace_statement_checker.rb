# frozen_string_literal: true

require "dependency_graph/sql_utils/base_statement_checker"

# Adapted from:
# https://github.com/github/github/blob/master/lib/github/sql_checkers/schema_domain/statement_checker.rb

# This class inspects SQL query statements for references to tables from different
# keyspaces, reporting them or raising an error, depending on configuration, if so.
#
# Notes: The SQL "parsing" here is very limited. One trivial failure scenario is a name
# shared between a table and a column, for example.
module DependencyGraph::SqlUtils

  class CrossKeyspaceQueryError < StandardError; end
  class CrossKeyspaceTransactionError < StandardError; end

  class CrossKeyspaceStatementChecker < DependencyGraph::SqlUtils::BaseStatementChecker

    ###
    # A list of all tables in the database, unsorted.
    ALL_TABLES = %w[
      dg_abstract_package_dependencies
      dg_abstract_package_dependency_counts
      dg_abstract_repository_dependencies
      dg_abstract_repository_dependency_counts
      dg_ar_internal_metadata
      dg_build_types
      dg_builds
      dg_checkpoints
      dg_dep_insights_backfills
      dg_dependency_specifications
      dg_etl_imports
      dg_failed_manifest_messages
      dg_key_values
      dg_locks
      dg_manifest_dependencies
      dg_manifests
      dg_package_release_dependent_counts
      dg_package_release_vuln_counts
      dg_package_versions
      dg_packages
      dg_repositories
      dg_schema_migrations
      dg_snapshot_blobs
      dg_snapshots
      dg_star_counts
      dg_vulnerable_version_ranges
    ]

    # Really just an identifier for tables that aren't going to be in a sharded keyspace.
    DEFAULT_KEYSPACE_NAME = "unsharded"

    ###
    # A map keyed by the keyspace "name" (can be anything that identifies a group of tables),
    # with values being arrays of table names in that keyspace.
    SHARDED_KEYSPACES = {
      "manifests": %w[dg_manifests dg_manifest_dependencies dg_repositories dg_star_counts]
    }

    QUERY_EXEMPTION_COMMENT_PATTERN = %r{/\*.*cross-keyspace-query-exempted.*\*/}
    TRANSACTION_EXEMPTION_COMMENT_PATTERN = %r{/\*.*cross-keyspace-transaction-exempted.*\*/}
    REMOVE_QUOTED_VALUES_REGEX = /(?<![\\])'(?:[^']|(?<=[\\])')*'/m.freeze

    EXCLUDED_TABLES = [
      # Add tables that should be ignored here.
    ]

    # The return value for cross_keyspaces_and_tables_referenced of a
    # query that doesn't violate any boundaries.
    EMPTY_RESULT = [[].freeze, [].freeze].freeze

    def initialize(**args)
      @all_tables = args[:all_tables] || ALL_TABLES
      @sharded_keyspaces = args[:sharded_keyspaces] || SHARDED_KEYSPACES
      super(**args.except(:all_tables, :sharded_keyspaces))
    end

    def check(queries:)
      stats_reporter.time_dist(time_metric_name) do
        # Remove any text values that might incidentally contain table names or keywords.
        queries = remove_quoted_values_from_sql(queries)

        all_queries = queries.join("\n")
        crossed_keyspaces, crossed_tables = cross_keyspaces_and_tables_referenced(all_queries)

        if crossed_keyspaces.any?
          exempted = exemption_comment_pattern.match?(all_queries)

          report_metrics(exempted, crossed_keyspaces)

          return if exempted
          return if !report_errors? && !raise_errors? && !log_errors?

          written_keyspaces = cross_keyspaces_written_to(queries)

          error_context = {
            written_keyspaces: written_keyspaces,
            crossed_keyspaces: crossed_keyspaces,
            crossed_tables: crossed_tables
          }

          raise_and_report_error("dependency-graph-api", queries, queries[0], caller, **error_context)
        end
      end
    end

    private

    def table_names_regex
      @table_names_regex ||= Regexp.new("(?<=[,`\\s])(?:#{@all_tables.join("|")})(?=[,`\\s])", "i")
    end

    def table_keyspaces
      return @table_keyspaces if @table_keyspaces

      @table_keyspaces = {}
      @all_tables.each do |table|
        @sharded_keyspaces.each do |keyspace, tables|
          if tables.include?(table)
            @table_keyspaces[table] = keyspace
            break
          end
        end
        @table_keyspaces[table] ||= "unsharded"
      end
      @table_keyspaces
    end

    def keyspace_for(table)
      table_keyspaces[table]
    end

    def same_keyspace?(tables)
      keyspaces = tables.map { |table| table_keyspaces[table] }.compact.uniq
      return keyspaces.length == 1
    end

    def exemption_comment_pattern
      if checking_transactions?
        TRANSACTION_EXEMPTION_COMMENT_PATTERN
      else
        QUERY_EXEMPTION_COMMENT_PATTERN
      end
    end

    def report_metrics(exempted, keyspaces)
      metric_name = if checking_transactions?
        "keyspaces.cross_keyspace_transaction"
      else
        "keyspaces.cross_keyspace_query"
      end

      keyspaces.each do |keyspace|
        stats_reporter.increment(metric_name, exempted: exempted, keyspace: keyspace)
      end
    end

    def time_metric_name
      if checking_transactions?
        "keyspaces.cross_keyspace_transactions_check"
      else
        "keyspaces.cross_keyspace_queries_check"
      end
    end

    def cross_keyspaces_and_tables_referenced(query)
      queried_tables = referenced_tables_from_sql(query)
      queried_tables -= EXCLUDED_TABLES

      return EMPTY_RESULT if same_keyspace?(queried_tables)

      queried_keyspaces = queried_tables.each_with_object(Set.new) do |table, keyspaces|
        keyspaces << keyspace_for(table).to_s
      end

      return [queried_keyspaces, queried_tables]
    end

    def referenced_tables_from_sql(query)
      query.scan(table_names_regex).uniq
    end

    def cross_keyspace_queries_from_transactions_sql(query)
      query.scan("")
    end

    def cross_keyspaces_written_to(queries)
      write_queries = queries.select do |query|
        query.match?(/\A\s*(INSERT|UPDATE)/i)
      end

      written_keyspaces = write_queries.each_with_object(Set.new) do |write_query, keyspaces|
        written_tables = referenced_tables_from_sql(write_query)
        written_tables -= EXCLUDED_TABLES

        written_tables.each do |table|
          keyspaces << keyspace_for(table).to_s
        end
      end

      written_keyspaces
    end

    def error_for(message)
      klass = if checking_transactions?
        CrossKeyspaceTransactionError
      else
        CrossKeyspaceQueryError
      end

      klass.new(message)
    end

    def error_message(queries, query, frame, **context)
      crossed_keyspaces = context[:crossed_keyspaces]
      written_keyspaces = context[:written_keyspaces]
      tables = context[:crossed_tables]
      grouped_by_keyspace = tables.group_by { |table| keyspace_for(table).to_s }
      table_detail = grouped_by_keyspace.transform_keys { |keyspace| "From `#{keyspace}` keyspace" }.to_yaml.delete_prefix("---").chomp

      String.new("\n\n") << <<~MSG
          Unsafe mix of tables from different keyspaces (`#{grouped_by_keyspace.keys.sort.join("`, `")}`) in #{"transactional " if checking_transactions?}query:
          #{table_detail}
          #{"Written to multiple keyspaces: `#{written_keyspaces.sort.join("`, `")}`\n" if written_keyspaces.size > 1}
          #{queries.join("\n")}

          These tables will be separated at the schema level in the (near) future.

          Called from `#{frame}`.
        MSG
    end
  end
end
