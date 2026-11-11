# frozen_string_literal: true

require "dependency_graph/sql_utils/base_statement_checker"

# Adapted from:
# https://github.com/github/github/blob/master/lib/github/sql_checkers/statement_checker.rb

# This class inspects SQL query statements for references to sharded database tables
# and checks whether the correct sharding key is present in the query. If not, it
# reports them or raises an error, depending on configuration.
#
# Notes: The SQL "parsing" here is very limited. One trivial failure scenario is a name
# shared between a table and a column, for example.
module DependencyGraph::SqlUtils

  class QueryWithoutShardingKeyError < StandardError; end

  class ShardingKeyMissingStatementChecker < DependencyGraph::SqlUtils::BaseStatementChecker

    QUERY_EXEMPTION_COMMENT_PATTERN = %r{/\*.*cross-shard-query-exempted(?:-permanent)?.*\*/}
    REMOVE_QUOTED_VALUES_REGEX = /(?<![\\])'(?:[^']|(?<=[\\])')*'/m.freeze

    INCLUDED_TABLES = {
      "dg_manifests" => { sharding_key: "github_repository_id" },
      "dg_manifest_dependencies" => { sharding_key: "github_repository_id" },
      "dg_repositories" => { sharding_key: "github_repository_id" },
      "dg_star_counts" => { sharding_key: "github_repository_id" },
    }

    PRIMARY_KEY = "id"
    EMPTY_RESULT = [].freeze

    def check(queries:)
      # Remove any text values that might incidentally contain table names or keywords.
      queries = remove_quoted_values_from_sql(queries)
      queries.each do |query|
        stats_reporter.time_dist("table_sharding.cross_shard_queries_check") do
          return unless relevant_query?(query)

          # since we are not parsing the SQL fully, we can remove surplus parentheses to make it easier for the linter
          tables = tables_without_sharding_key_referenced(query.gsub(/[()]/, " "))

          if tables.any?
            matchdata = QUERY_EXEMPTION_COMMENT_PATTERN.match(query)
            exempted = matchdata.present?
            permanent = matchdata.to_s.include?("permanent")

            report_metrics(query, tables, exempted, permanent)

            return if exempted
            return if !report_errors? && !raise_errors? && !log_errors?

            raise_and_report_error("dependency-graph-api", queries, query, caller, tables: tables)
          end
        end
      end
    end

    private

    def tables_without_sharding_key_referenced(query)
      queried_tables = referenced_tables_from_sql(query)

      return EMPTY_RESULT if queried_tables.empty?

      regexes_by_table = queried_tables.each_with_object({}) do |table, hash|
        sharding_key = INCLUDED_TABLES[table][:sharding_key]
        table_alias = if match = alias_regex(table).match(query)
          match.captures.first
        else
          table
        end

        hash[table] = column_with_optional_table_regex(table_alias, sharding_key)
      end

      return EMPTY_RESULT if regexes_by_table.values.all? { |r| r.match?(query) }

      regexes_by_table.reject do |_, r|
        r.match?(query)
      end.map(&:first)
    end

    def alias_regex(table)
      @alias_regex ||= Hash.new do |h, k|
        h[k] = Regexp.new("\s+[,`\\s]?#{table}[,`\\s]?\s+[,`\\s]?(\S+)[,`\\s]?\s+", "i")
      end
      @alias_regex[table]
    end

    def column_with_optional_table_regex(table, sharding_key)
      @column_with_optional_table_regex ||= Hash.new do |h, k|
        table_arg, sharding_key_arg = k

        with_table = column_with_table_regex(table_arg, sharding_key_arg)
        without_table_with_sharding_key = column_regex(column_name: sharding_key_arg)
        without_table_with_primary_key = column_regex(column_name: PRIMARY_KEY)

        h[k] = Regexp.union(
          with_table,
          Regexp.union(without_table_with_sharding_key, without_table_with_primary_key)
        )
      end
      @column_with_optional_table_regex[[table, sharding_key]]
    end

    def column_with_table_regex(table, sharding_key)
      @column_with_table_regex ||= Hash.new do |h, k|
        table_arg, sharding_key_arg = k

        with_sharding_key = column_regex(table_name: table_arg, column_name: sharding_key_arg)
        with_primary_key = column_regex(table_name: table_arg, column_name: PRIMARY_KEY)

        h[k] = Regexp.union(with_sharding_key, with_primary_key)
      end
      @column_with_table_regex[[table, sharding_key]]
    end

    def column_regex(table_name: nil, column_name:)
      regex_string = if table_name
        "([,`\\s]?)(#{table_name})([,`\\s]?)\.([,`\\s]?)(#{column_name})([,`\\s]?)"
      else
        "([\s]+)([,`\\s]?)(#{column_name})([,`\\s]?)"
      end

      Regexp.new("(#{regex_string}\s*=)|(=\s*#{regex_string})", "i")
    end

    def table_names_regex
      @table_names_regex ||= Regexp.new("(?<=[,`\\s])(?:#{INCLUDED_TABLES.keys.join("|")})(?=[,`\\s])", "i")
    end

    def referenced_tables_from_sql(query)
      query.scan(table_names_regex).uniq
    end

    def relevant_query?(query)
      query.starts_with?(/\s*(SELECT|UPDATE|DELETE)/i)
    end

    def report_metrics(query, tables, exempted, permanent)
      metric_name = "table_sharding.query_without_sharding_key"

      query_type = query.match(/\A\s*(SELECT|UPDATE|DELETE)/i).captures.first&.downcase
      primary_key_only = query.match?(/WHERE\s+#{PRIMARY_KEY}\s*=\s*\d+\s*\z/i)

      tables.each do |table|
        tags = {
          table: table,
          exempted: exempted,
          permanent: permanent,
          query_type: query_type,
          primary_key_only: primary_key_only,
        }

        stats_reporter.increment(metric_name, **tags)
      end
    end

    def error_for(message)
      QueryWithoutShardingKeyError.new(message)
    end

    def error_message(queries, query, frame, **context)
      tables = context[:tables]
      sharding_key_details = tables.map { |table| "- #{table}.#{INCLUDED_TABLES[table][:sharding_key]}" }.join("\n")

      String.new("\n\n") << <<~MSG
          Inefficient query for sharded database tables: #{tables.join(", ")}.

          For each table, the corresponding sharding key needs to be part of the query:
          #{sharding_key_details}

          #{query}

          Called from `#{frame}`.
        MSG
    end
  end
end
