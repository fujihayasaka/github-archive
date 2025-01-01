# typed: true
# frozen_string_literal: true

require "github/stack_filter"
require "github/sql/digester"
require "github/sql_checkers/statement_checker"

# This class inspects SQL query statements for references to sharded database tables
# and checks whether the correct sharding key is present in the query. If not, it
# reports them or raises an error, depending on configuration.
#
# Notes: The SQL "parsing" here is very limited. One trivial failure scenario is a name
# shared between a table and a column, for example.
class GitHub::SQLCheckers::TableSharding::StatementChecker < GitHub::SQLCheckers::StatementChecker
  QUERY_EXEMPTION_COMMENT_PATTERN = %r{/\*.*cross-shard-query-exempted(?:-permanent)?.*\*/}
  RELEVANT_QUERY_REGEX = /(?:\s*\/\*.*?\*\/\s*)*\s*(SELECT|UPDATE|DELETE)/i.freeze

  INCLUDED_TABLES = {
    "code_scanning_alerts" => { sharding_key: "repository_id", owning_team: "code-scanning-experiences" },
    "code_scanning_check_suites" => { sharding_key: "repository_id", owning_team: "code-scanning-experiences" },
    "pushes" => { sharding_key: "repository_id", owning_team: "coding" },
    "workflow_run_executions" => { sharding_key: "repository_id", owning_team: "c2c-actions-experience" },
    "workflow_job_runs" => { sharding_key: "repository_id", owning_team: "c2c-actions-checks" },
    "ref_pushes" => { sharding_key: "repository_id", owning_team: "repos" },
    "repository_rule_runs" => { sharding_key: "repository_id", owning_team: "repos", require_sharding_key: true },
    "repository_rule_suites" => { sharding_key: "repository_id", owning_team: "repos", require_sharding_key: true },
    "repository_rule_suite_source_results" => { sharding_key: "repository_id", owning_team: "repos", require_sharding_key: true },
    "event_action_ref_updates" => { sharding_key: "repository_id", owning_team: "repos", require_sharding_key: true },
    "event_action_repository_operations" => { sharding_key: "repository_id", owning_team: "repos", require_sharding_key: true },
  }

  PRIMARY_KEY = "id"
  EMPTY_RESULT = [].freeze

  def check(queries:, connection_class: nil)
    queries.each do |query|
      stats_reporter.time("table_sharding.cross_shard_queries_check") do
        return unless relevant_query?(query)

        # since we are not parsing the SQL fully, we can remove surplus parentheses to make it easier for the linter
        tables = tables_without_sharding_key_referenced(query.gsub(/[()]/, " "))

        if tables.any?
          matchdata = QUERY_EXEMPTION_COMMENT_PATTERN.match(query)
          exempted = matchdata.present?
          permanent = matchdata.to_s.include?("permanent")

          report_metrics(query, tables, exempted, permanent)

          return if exempted
          return if !report_errors? && !raise_errors?

          raise_and_report_error("github-data-partitioning", queries, query, caller, tables: tables)
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

      if INCLUDED_TABLES.dig(table_arg, :require_sharding_key)
        h[k] = Regexp.union(
          with_table,
          without_table_with_sharding_key
        )
      else
        h[k] = Regexp.union(
          with_table,
          without_table_with_sharding_key,
          without_table_with_primary_key
        )
      end
    end
    @column_with_optional_table_regex[[table, sharding_key]]
  end

  def column_with_table_regex(table, sharding_key)
    @column_with_table_regex ||= Hash.new do |h, k|
      table_arg, sharding_key_arg = k

      with_sharding_key = column_regex(table_name: table_arg, column_name: sharding_key_arg)
      with_primary_key = column_regex(table_name: table_arg, column_name: PRIMARY_KEY)

      if INCLUDED_TABLES.dig(table_arg, :require_sharding_key)
        h[k] = with_sharding_key
      else
        h[k] = Regexp.union(with_sharding_key, with_primary_key)
      end
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
    query.starts_with?(RELEVANT_QUERY_REGEX)
  end

  def report_metrics(query, tables, exempted, permanent)
    metric_name = "table_sharding.cross_shard_query"

    query_type = query.match(/\A(?:\s*\/\*.*?\*\/\s*)*\s*(SELECT|UPDATE|DELETE)/i).captures.first&.downcase
    primary_key_only = query.match?(/WHERE\s+#{PRIMARY_KEY}\s*=\s*\d+\s*\z/i)

    tables.each do |table|
      tags = [
        "domain:#{GitHub::SQLCheckers::SchemaDomain.for(table)}",
        "table:#{table}",
        "exempted:#{exempted}",
        "permanent:#{permanent}",
        "query_type:#{query_type}",
        "primary_key_only:#{primary_key_only}",
      ]

      GitHub.dogstats.increment(metric_name, tags: tags)
    end
  end

  def error_for(message)
    GitHub::SQLCheckers::TableSharding::CrossShardQueryError.new(message)
  end

  def error_message(queries, query, frame, **context)
    tables = context[:tables]
    sharding_key_details = tables.map { |table| "- #{table}.#{INCLUDED_TABLES[table][:sharding_key]} (owning team: #{INCLUDED_TABLES[table][:owning_team]})" }.join("\n")

    String.new("\n\n") << <<~MSG
        Inefficient query for sharded database tables: #{tables.join(", ")}.

        For each table, the corresponding sharding key needs to be part of the query:
        #{sharding_key_details}

        #{query}

        Called from `#{frame}`.
      MSG
  end
end
