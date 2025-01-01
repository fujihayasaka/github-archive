# typed: true
# frozen_string_literal: true

require "github/stack_filter"
require "github/sql/digester"
require "github/sql_checkers/statement_checker"

# This class inspects SQL query statements for references to tables from different
# schema domains, reporting them or raising an error, depending on configuration, if so.
#
# See https://thehub.github.com/engineering/development-and-ops/dotcom/schema-domains/ for more context.
#
# Notes: The SQL "parsing" here is very limited. One trivial failure scenario is a name
# shared between a table and a column, for example.
class GitHub::SQLCheckers::SchemaDomain::StatementChecker < GitHub::SQLCheckers::StatementChecker
  QUERY_EXEMPTION_COMMENT_PATTERN = %r{/\*.*cross-schema-domain-query-exempted.*\*/}
  TRANSACTION_EXEMPTION_COMMENT_PATTERN = %r{/\*.*cross-schema-domain-transaction-exempted.*\*/}
  REMOVE_QUOTED_VALUES_REGEX = /(?<![\\])'(?:[^']|(?<=[\\])')*'/m.freeze
  WRITE_QUERY_REGEX = /\A\s*(INSERT|UPDATE)/i.freeze

  # The return value for cross_domains_and_tables_referenced of a
  # query that doesn't violate any boundaries.
  EMPTY_RESULT = [[].freeze, [].freeze].freeze

  def check(queries:, connection_class: nil)
    stats_reporter.time(time_metric_name) do
      all_queries = queries.join("\n")
      crossed_domains, crossed_tables = cross_domains_and_tables_referenced(all_queries)

      if crossed_domains.any?
        exempted = exemption_comment_pattern.match?(all_queries)

        report_metrics(exempted, crossed_domains)

        return if exempted
        return if !report_errors? && !raise_errors?

        written_domains = cross_domains_written_to(queries)

        error_context = {
          written_domains: written_domains,
          crossed_domains: crossed_domains,
          crossed_tables: crossed_tables
        }

        raise_and_report_error("github-data-partitioning", queries, queries[0], caller, **error_context)
      end
    end
  end

  private

  def exemption_comment_pattern
    if checking_transactions?
      TRANSACTION_EXEMPTION_COMMENT_PATTERN
    else
      QUERY_EXEMPTION_COMMENT_PATTERN
    end
  end

  def report_metrics(exempted, domains)
    metric_name = if checking_transactions?
      "schema_domains.cross_domain_transaction"
    else
      "schema_domains.cross_domain_query"
    end

    domains.each do |domain|
      GitHub.dogstats.increment(metric_name, tags: ["exempted:#{exempted}", "domain:#{domain}"])
    end
  end

  def time_metric_name
    if checking_transactions?
      "schema_domains.cross_domain_transactions_check"
    else
      "schema_domains.cross_domain_queries_check"
    end
  end

  def cross_domains_and_tables_referenced(query)
    queried_tables = referenced_tables_from_sql(query)

    return EMPTY_RESULT if GitHub::SQLCheckers::SchemaDomain.same?(queried_tables)

    queried_domains = queried_tables.each_with_object(Set.new) do |table, domains|
      domains << GitHub::SQLCheckers::SchemaDomain.for(table).to_s
    end

    [queried_domains, queried_tables]
  end

  def referenced_tables_from_sql(query)
    GitHub::SQLCheckers::TableParser.run(query)
  end

  def cross_domain_queries_from_transactions_sql(query)
    query.scan("")
  end

  def cross_domains_written_to(queries)
    write_queries = queries.select do |query|
      query.match?(WRITE_QUERY_REGEX)
    end

    written_domains = write_queries.each_with_object(Set.new) do |write_query, domains|
      written_tables = referenced_tables_from_sql(write_query)

      written_tables.each do |table|
        domains << GitHub::SQLCheckers::SchemaDomain.for(table).to_s
      end
    end

    written_domains
  end

  def error_for(message)
    klass = if checking_transactions?
      GitHub::SQLCheckers::SchemaDomain::CrossDomainTransactionError
    else
      GitHub::SQLCheckers::SchemaDomain::CrossDomainQueryError
    end

    klass.new(message)
  end

  def error_message(queries, query, frame, **context)
    crossed_domains = context[:crossed_domains]
    written_domains = context[:written_domains]
    tables = context[:crossed_tables]
    grouped_by_domain = tables.group_by { |table| GitHub::SQLCheckers::SchemaDomain.for(table).to_s }
    table_detail = grouped_by_domain.transform_keys { |domain| "From `#{domain}` domain" }.to_yaml.delete_prefix("---").chomp

    String.new("\n\n") << <<~MSG
        Unsafe mix of tables from different schema domains (`#{grouped_by_domain.keys.sort.join("`, `")}`) in #{"transactional " if checking_transactions?}query:
        #{table_detail}
        #{"Written to multiple domains: `#{written_domains.sort.join("`, `")}`\n" if written_domains.size > 1}
        #{queries.join("\n")}

        These tables will be separated at the schema level in the (near) future.

        Please see https://thehub.github.com/engineering/development-and-ops/dotcom/schema-domains/#what-to-do-when-a-query-would-cross-domain-boundaries for more information and guidance on how to fix this.

        Called from `#{frame}`.
      MSG
  end
end
