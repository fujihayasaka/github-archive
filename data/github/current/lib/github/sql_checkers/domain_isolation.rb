# typed: true
# frozen_string_literal: true

module GitHub::SQLCheckers::DomainIsolation
  # A query uses tables owned by multiple packages
  class CrossDomainQueryError < Exception; end

  # A query was not issued via the public interface of the package that owns the table
  class DomainAccessError < Exception; end

  # This annotation is only used for testing setup and should not be used in production code
  CROSS_DOMAIN_QUERY_EXEMPTION_ANNOTATION = "cross-domain-query-exempted"

  SENTRY_PROJECT_NAME = "github-domain-isolation"

  IGNORED_PATHS = [
    %r{\Aapp\/api\/app},
    %r{\Aapp\/api\/app\.rb},
    %r{\Aapp\/helpers\/pagination_helper},
    %r{\Aapp\/jobs\/hydro_message_job},
    %r{\Aapp\/jobs\/set_zuora_background_client},
    %r{\Aapp\/jobs\/smart_database_selection},
    %r{\Aapp\/jobs\/timed_job},
    %r{\Aapp\/platform\/batch},
    %r{\Aapp\/platform\/connection_wrappers\/relation\.rb},
    %r{\Aapp\/platform\/connections\/base\.rb},
    %r{\Aapp\/platform\/loader},
    %r{\Aapp\/platform\/objects\/base\/graph_ql_graceful_degradation_extension\.rb},
    %r{\Alib\/active_job},
    %r{\Alib\/application_record},
    %r{\Alib\/audit\/test\/service},
    %r{\Alib\/configurable},
    %r{\Alib\/context},
    %r{\Alib\/database_selector},
    %r{\Alib\/gh},
    %r{\Alib\/github\/active_record_enumerable_protection},
    %r{\Alib\/github\/active_record},
    %r{\Alib\/github\/association_instrumenter},
    %r{\Alib\/github\/batched_scope},
    %r{\Alib\/github\/config},
    %r{\Alib\/github\/connection_adapter_disabler},
    %r{\Alib\/github\/current_tenant},
    %r{\Alib\/github\/memory_dogstats_d},
    %r{\Alib\/github\/mysql_instrumenter},
    %r{\Alib\/github\/null_dogstatsd},
    %r{\Alib\/github\/prefill_associations},
    %r{\Alib\/github\/rate_limited_creation},
    %r{\Alib\/github\/redis},
    %r{\Alib\/github\/request_duration_manager},
    %r{\Alib\/github\/service_mapping},
    %r{\Alib\/github\/simple_pagination},
    %r{\Alib\/github\/sql},
    %r{\Alib\/github\/throttler},
    %r{\Alib\/github\/transition},
    %r{\Alib\/instrumentation},
    %r{\Apackages\/app_security\/app\/models\/conditional_access\/filter},
    %r{\Apackages\/application\/app\/jobs\/application_job},
    %r{\Apackages\/git\/app\/models\/github\/sql_cursor},
    %r{\Apackages\/substrate\/app\/models\/slow_query_logger},
    %r{\Atest\/},
    %r{test_case\.rb},
    %r{test_helper\.rb},
    %r{test\.rb},
  ].freeze

  IGNORED_PATHS_REGEX = Regexp.union(IGNORED_PATHS)

  def self.backtrace_cleaner_for(package)
    @package_backtrace_cleaner ||= {}
    return @package_backtrace_cleaner[package] if @package_backtrace_cleaner[package]

    root = "#{Rails.root}/"
    @package_backtrace_cleaner[package] = begin
      backtrace_cleaner = ::Rails::BacktraceCleaner.new
      backtrace_cleaner.remove_silencers!
      backtrace_cleaner.add_filter { |line| line.start_with?(root) ? line.from(root.size) : line }
      backtrace_cleaner.add_silencer { |line| !/\A(?:\.\/)?(?:app|config|lib|test|packages|\(\w*\))/.match?(line) }
      backtrace_cleaner.add_silencer { |line| IGNORED_PATHS_REGEX.match?(line) }
      backtrace_cleaner
    end
  end
end

require "github/sql_checkers/stacktrace_parser"
require "github/sql_checkers/statement_checker"
require "github/sql_checkers/domain_isolation/tables_statement_checker"
