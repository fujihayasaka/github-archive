# typed: true
# frozen_string_literal: true

require_relative "../../instrumentation/stats_reporter"

# A base object for statement checker. Intended to be used with Instrumentation::QuerySubscriber.

module GitHub::SQLCheckers
  class StatementChecker
    def initialize(raise_errors: false, report_errors: false, log_errors: false, checking_transactions: false, stats_reporter: ::Instrumentation::NoOpStatsReporter.new)
      @raise_errors = raise_errors
      @report_errors = report_errors
      @log_errors = log_errors
      @checking_transactions = checking_transactions
      @stats_reporter = stats_reporter
    end

    def check(queries: [], connection_class: nil)
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
      return unless raise_errors? || report_errors? || log_errors?

      raw_query = query
      queries = scrub_values_from_queries(queries)
      query = scrub_values_from_query(query)

      error = if context.key?(:error)
        context[:error]
      else
        frames = backtrace_cleaner.clean(this_stack)
        frame = frames.join("\n")
        e = error_for(error_message(queries, query, frame, **context))
        e.set_backtrace(frames)
        e
      end

      if log_errors?
        GitHub.logger.info({
          "code.namespace" => self.class,
          "code.function" => "raise_and_report_error",
          "code.callstack" => error,
          "gh.catalog_service" => GitHub.context[:catalog_service] || :unknown,
          "gh.request_id" => GitHub.context[:request_id],
        })
      end

      return unless report_errors? || raise_errors?

      if report_errors?
        Failbot.report!(error, app: failbot_app_name, rollup: rollup_for(queries))
      end

      if raise_errors?
        raise error
      end
    end

    def backtrace_cleaner
      @backtrace_cleaner ||= begin
        backtrace_cleaner = ::Rails::BacktraceCleaner.new
        backtrace_cleaner.add_silencer { |line| line.start_with?("lib/") }
        backtrace_cleaner
      end
    end

    def scrub_values_from_queries(queries)
      queries.map { |query| scrub_values_from_query(query) }
    end

    def scrub_values_from_query(query)
      GitHub::SQL::Digester.digest_sql(query) if query
    end

    def rollup_for(queries)
      Digest::SHA256.hexdigest(queries.join("\n"))
    end

    def skip_query?(query)
      query.starts_with?("SHOW FULL FIELDS FROM") ||
        query.starts_with?("SELECT column_name FROM information_schema.statistics") ||
        (query.starts_with?("SELECT table_name") && query.include?("information_schema.tables")) ||
        query.include?("flipper_features") ||
        query.include?("flipper_gates")
    end
  end
end
