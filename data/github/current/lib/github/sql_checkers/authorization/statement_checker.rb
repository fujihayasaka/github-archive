# typed: true
# frozen_string_literal: true

require "github/sql_checkers/statement_checker"

class GitHub::SQLCheckers::Authorization::StatementChecker < GitHub::SQLCheckers::StatementChecker
  ABILITIES_TABLE_REGEX = /(?<=[,`\s])(?:abilities)(?=[,`\s])/i.freeze

  # emits metrics if query hits abilities table
  def check(queries:, connection_class: nil)
    all_queries = queries.join("\n")
    abilities_query_found = check_for_abilities_query(all_queries)
    return unless abilities_query_found

    tags = GitHub::SQLCheckers::StacktraceParser.first_relevant_frame_info(caller)
    return unless tags

    report_metrics(tags)
  end

  def report_metrics(tags)
    file = tags[:path]
    method = tags[:method]
    GitHub.dogstats.increment "abilities_query.executed", tags: ["file:#{file}", "method:#{method}"]
  end

  # returns true or false
  def check_for_abilities_query(queries)
    queries.match?(ABILITIES_TABLE_REGEX)
  end
end
