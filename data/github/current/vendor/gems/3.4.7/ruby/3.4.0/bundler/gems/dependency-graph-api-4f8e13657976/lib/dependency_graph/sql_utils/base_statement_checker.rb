# typed: true
# frozen_string_literal: true

require "dependency_graph/sql_utils/stack_filter"
require "dependency_graph/sql_utils/sql_digester"

# A base object for statement checker. Intended to be used with Instrumentation::QuerySubscriber.
#
module DependencyGraph::SqlUtils
  class BaseStatementChecker
    REMOVE_QUOTED_VALUES_REGEX = /(?<![\\])'(?:[^']|(?<=[\\])')*'/m.freeze

    def initialize(raise_errors: false, report_errors: false, log_errors: false, checking_transactions: false, stats_reporter: Instrument)
      @raise_errors = raise_errors
      @report_errors = report_errors
      @log_errors = log_errors
      @checking_transactions = checking_transactions
      @stats_reporter = stats_reporter
    end

    def check(queries: [])
      raise NotImplementedError, "check(queries: []) must be implemented by subclasses"
    end

    private

    def checking_transactions?; @checking_transactions; end
    def raise_errors?; @raise_errors; end
    def report_errors?; @report_errors; end
    def log_errors?; @log_errors; end
    def stats_reporter; @stats_reporter; end

    def error_for(message)
      raise NotImplementedError, "error_for(message) must be implemented by subclasses"
    end

    def error_message(queries, query, frame, **context)
      raise NotImplementedError, "error_message(queries, query, frame, **context) must be implemented by subclasses"
    end

    def raise_and_report_error(failbot_app_name, queries, query, this_stack, **context)
      queries = scrub_values_from_queries(queries)
      query = scrub_values_from_query(query)
      frame = DependencyGraph::SqlUtils::StackFilter.first_significant_frame(this_stack)
      err_msg = error_message(queries, query, frame, **context)
      error = error_for(err_msg)

      if log_errors?
        DependencyGraph.logger.info(err_msg,
          "code.namespace": self.class.name,
          "code.function": "raise_and_report_error",
          "gh.catalog_service": "dependency_graph_api",
          "exception.stacktrace": frame,
          "gh.dependency_graph.sql.query": query,
          "gh.dependency_graph.sql.checker": self.class.name,
          "db.sql.table": context[:tables]&.join(", ")
        )
      end

      if report_errors?
        error.set_backtrace(caller)
        Failbot.report!(error, rollup: rollup_for(queries))
      end

      if raise_errors?
        raise error
      end
    end

    # Replace substrings between single-quotes ('), allowing for escaped single quotes
    def remove_quoted_values_from_sql(queries)
      queries.map do |query|
        query.gsub(REMOVE_QUOTED_VALUES_REGEX, "'...'")
      end
    end

    def scrub_values_from_queries(queries)
      queries.map { |query| scrub_values_from_query(query) }
    end

    def scrub_values_from_query(query)
      DependencyGraph::SqlUtils::SqlDigester.digest_sql(query)
    end

    def rollup_for(queries)
      Digest::SHA256.hexdigest(queries.join("\n"))
    end

  end
end
