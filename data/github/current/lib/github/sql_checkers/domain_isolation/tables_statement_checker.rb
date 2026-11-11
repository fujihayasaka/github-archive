# typed: true
# frozen_string_literal: true

# This checker is responsible for ensuring SQL queries involving domain package
# private tables are only executed by the domain package that owns the table, and
# through the domain's interface.
class GitHub::SQLCheckers::DomainIsolation::TablesStatementChecker < GitHub::SQLCheckers::StatementChecker
  sig do
    params(
      queries: T::Array[String],
      connection_class: T.nilable(Class)
    ).void
  end
  def check(queries:, connection_class: nil)
    return unless checking_enabled?
    return if skip_query?(queries.join("\n"))

    queries.map do |query_text|
      query = Query.new(query_text)
      next if query.can_skip?

      query.table_to_packages_and_ownership.each do |table, (package, level)|
        next if package.nil?
        next if GitHub.packageowners.ignored_queries(package).include?(query.digest)

        # in some cases when executing this code, `query.most_significant_frame` isn't correct
        # and we have to use the whole stacktrace to crossreference ignored frames.
        # it is always correct in the reported error
        next if GitHub.packageowners.ignored_frames(package).intersect?(query.normalized_frames)

        args = { query: query, table: table, package: package }

        skip_audit_only = !in_ci?
        should_raise = in_ci? || !GitHub.record_domain_query_violations?

        case level
        when GitHub::Serviceowners::Packageowners::TableVisibilityLevel::Audit
          next if skip_audit_only

          cross_domain_check(**args, should_raise: false)
          domain_access_check(**args, should_raise: false)
        when GitHub::Serviceowners::Packageowners::TableVisibilityLevel::Public
          cross_domain_check(**args, should_raise: should_raise)

          next if skip_audit_only
          domain_access_check(**args, should_raise: false)
        when GitHub::Serviceowners::Packageowners::TableVisibilityLevel::Private
          cross_domain_check(**args, should_raise: should_raise)
          domain_access_check(**args, should_raise: should_raise)
        end
      end
    end
  end

  private

  sig { params(query: Query, table: String, package: String, should_raise: T::Boolean).void }
  def cross_domain_check(query:, table:, package:, should_raise:)
    return if query.cross_domain_exempted?
    return if !query.cross_domain?

    # For cross-domain queries, we don't want to consider package boundaries.
    # We are interested in the exact location the query was executed from.
    query.package_to_consider = nil

    # Intentionally this check is as late as possible to avoid unnecessary work
    # by looking up the call stack with `caller`, see `Query#caller_frames`.
    return if query.cannot_process?

    if GitHub.record_domain_query_violations?
      query.record_violation(
        table,
        GitHub::Serviceowners::Packageowners::QueryViolationReason::CrossDomain
      )
    end
    return unless should_raise

    check_violation_and_raise_error(
      query, package,
      GitHub::Serviceowners::Packageowners::QueryViolationReason::CrossDomain,
      GitHub::SQLCheckers::DomainIsolation::CrossDomainQueryError
    )
  end

  sig { params(query: Query, table: String, package: String, should_raise: T::Boolean).void }
  def domain_access_check(query:, table:, package:, should_raise:)
    query.package_to_consider = package

    return if query.domain_access_correct?

    # Intentionally this check is as late as possible to avoid unnecessary work
    # by looking up the call stack with `caller`, see `Query#caller_frames`.
    return if query.cannot_process?

    if GitHub.record_domain_query_violations?
      query.record_violation(
        table,
        GitHub::Serviceowners::Packageowners::QueryViolationReason::DomainAccess
      )
    end
    return unless should_raise

    check_violation_and_raise_error(
      query,
      package,
      GitHub::Serviceowners::Packageowners::QueryViolationReason::DomainAccess,
      GitHub::SQLCheckers::DomainIsolation::DomainAccessError
    )
  end

  sig do
    params(
      query: Query, package: String,
      reason: GitHub::Serviceowners::Packageowners::QueryViolationReason,
      error_klass: T.class_of(Exception)
    ).void
  end
  def check_violation_and_raise_error(query, package, reason, error_klass)
    return if query.has_violation_tracked?(reason, package)

    error = query.build_error(error_klass)
    raise_and_report_error(
      GitHub::SQLCheckers::DomainIsolation::SENTRY_PROJECT_NAME,
      [query.text], nil, query.caller_frames, error: error
    )
  end

  # Domain isolation query checking is only enabled if:
  # 1. We're running in test with PERFORM_STATEMENT_CHECKING=1
  sig { returns(T::Boolean) }
  def checking_enabled?
    in_test?
  end

  # Used for stubbing in some tests
  sig { returns(T::Boolean) }
  def in_test?
    Rails.env.test?
  end

  sig { returns(T::Boolean) }
  def in_ci?
    ENV["GITHUB_CI"] == "1"
  end

  class Query

    sig { returns(String) }
    attr_reader :text
    sig { returns(T.nilable(String)) }
    attr_accessor :package_to_consider

    sig { params(text: String).void }
    def initialize(text)
      @text = text
    end

    sig { returns(T::Boolean) }
    def can_skip?
      tables.empty?
    end

    sig { returns(T::Boolean) }
    def cannot_process?
      caller_frames.empty?
    end

    sig { returns(String) }
    def scrubbed_text
      return @scrubbed_text if defined?(@scrubbed_text)

      @scrubbed_text = if text
        GitHub::SQL::Digester.digest_sql(text)
      end
    end

    sig { returns(String) }
    def digest
      return @digest if defined?(@digest)

      @digest = if text
        Digest::SHA256.hexdigest(scrubbed_text)
      end
    end

    sig { returns(Integer) }
    def cache_key
      text.hash
    end

    sig { returns(T::Hash[Integer, T::Array[String]]) }
    def query_to_tables_cache
      @@query_to_tables_cache ||= Hash.new { |h, k| h[k] = [] }
    end

    sig { returns(T::Array[String]) }
    def tables
      return @tables if defined?(@tables)
      return @tables = T.must(query_to_tables_cache[cache_key]) if query_to_tables_cache.key?(cache_key)

      @tables = GitHub::SQLCheckers::TableParser.run(text).tap do |tables|
        tables.freeze

        query_to_tables_cache[cache_key] = tables
      end
    end

    sig do
      returns(T::Hash[String, [String, GitHub::Serviceowners::Packageowners::TableVisibilityLevel]])
    end
    def table_to_packages_and_ownership
      return @table_to_packages_and_ownership if defined?(@table_to_packages_and_ownership)

      @table_to_packages_and_ownership = tables.each_with_object(Hash.new) do |table, hash|
        hash[table] = GitHub.packageowners.package_and_ownership_level_for(table)
      end
    end

    sig { returns(T.nilable(String)) }
    def first_package
      _, package_and_ownership = table_to_packages_and_ownership.find { |_, (package, _)| package.present? }
      package, _ = package_and_ownership

      package
    end

    sig { returns(T::Boolean) }
    def cross_domain?
      return @cross_domain if defined?(@cross_domain)
      @cross_domain = table_to_packages_and_ownership.values.uniq(&:first).size > 1
    end

    sig { returns(T::Boolean) }
    def cross_domain_exempted?
      return @exempted if defined?(@exempted)
      @exempted = text.include?(GitHub::SQLCheckers::DomainIsolation::CROSS_DOMAIN_QUERY_EXEMPTION_ANNOTATION)
    end

    sig { returns(T::Boolean) }
    def domain_access_correct?
      (
        GitHub.packageowners.calling_package_matches_table_package?(tables) &&
        GitHub::SQLCheckers::DomainIsolation::DOMAIN_BOUNDARY_REGEX.match?(most_significant_frame)
      )
    end

    sig do
      params(reason: GitHub::Serviceowners::Packageowners::QueryViolationReason, package: T.nilable(String)).
      returns(T::Boolean)
    end
    def has_violation_tracked?(reason, package = first_package)
      return false if package.nil?

      GitHub.packageowners.violation_tracked?(
        package, scrubbed_text, reason
      )
    end

    sig { params(table: String, reason: GitHub::Serviceowners::Packageowners::QueryViolationReason).void }
    def record_violation(table, reason)
      GitHub.packageowners.record_violation(
        table, scrubbed_text, most_significant_frame, reason
      )
    end

    # returns ruby-style frames, eg:
    #  ["lib/github/callback_instrumenter.rb:60:in 'block in GitHub::CallbackInstrumenter#after_create'"]
    sig { returns(T::Array[String]) }
    def caller_frames
      return @caller_frames[package_to_consider] if defined?(@caller_frames)

      caller = Kernel.caller
      @caller_frames = Hash.new do |hash, key|
        hash[key] = GitHub::SQLCheckers::DomainIsolation.backtrace_cleaner_for(key).clean(caller)
      end

      @caller_frames[package_to_consider]
    end

    # returns frames as [relative path]:[line number]
    # eg: ["packages/issues/app/models/issue.rb:2732"]
    sig { returns(T::Array[String]) }
    def normalized_frames
      @normalized_frames ||= caller_frames.map do |frame|
        frame[/(#{Rails.root})?(\/)?(.+:\d+)/, 3]
      end.compact
    end

    sig { returns(T.nilable(String)) }
    def most_significant_frame
      caller_frames.first
    end

    sig { params(klass: T.class_of(Exception)).returns(Exception) }
    def build_error(klass)
      ErrorBuilder.new(self).build(klass)
    end
  end

  class ErrorBuilder

    sig { returns(Query) }
    attr_reader :query

    sig { params(query: Query).void }
    def initialize(query)
      @query = query
    end

    sig { params(klass: T.class_of(Exception)).returns(Exception) }
    def build(klass)
      message = String.new("\n\n") << <<~MSG
        #{"Read more about this error here: https://github.com/github/issues/discussions/16871" if tables_list.include?("'issues'")}

        #{intro(klass)}
        #{query_details}
        Tables:

        #{tables_list}

        To reproduce this error run:

            #{test_all_features_text}PERFORM_STATEMENT_CHECKING=1 bin/rails test <path_to_test_file>:<line_number>

        To record and track this error as a violation in `domain_isolation_todos.yml`, run this test with the following environment variables.
        This will update the query violation file(s) with the new violation(s).

            #{test_all_features_text}PERFORM_STATEMENT_CHECKING=1 DOMAIN_QUERY_VIOLATIONS=1 bin/rails test <path_to_test_file>:<line_number>

        You can also ignore it buy adding `domain-isolation-query-violation:ignore:[package name] ([query type])` (eg `domain-isolation-query-violation:ignore:packages/issues (SELECT)`) comment to the offending line and running `bin/packwerk update-todo`.

        If there are many violations to add or update, you can run the following command to pull all violations
        from the latest completed CI build on your branch.
        Before running it, check the package root folder (eg. `packages/issues`)
        for the `domain_query_violations.yml` or `domain_isolation_todos.yml`.
        Use `--format domain_query_violations` or `--format domain_isolation_todos` accordingly.
        If no ignore file is present yet, the `domain_query_todo` format is preferred.
        You can also run it with `--help`.

            script/domain-isolation-query-violations

        Called from:
      MSG

      klass.new(message).tap do |error|
        error.set_backtrace(query.caller_frames)
      end
    end

    sig { params(klass: T.class_of(Exception)).returns(T.nilable(String)) }
    def intro(klass)
      if klass == GitHub::SQLCheckers::DomainIsolation::CrossDomainQueryError
        <<~TEXT
          A SQL query involving tables owned by multiple domains was executed.

          Domains form a data access boundary. Only tables owned by the same domain package are allowed to be used
          together in SQL queries. Split this query up into separate ones to respect the data access boundaries and
          avoid adding new cross-domain query violations as much as possible.
        TEXT
      elsif klass == GitHub::SQLCheckers::DomainIsolation::DomainAccessError
        <<~TEXT
          A SQL query involving at least one private table was executed across domain boundaries.

          Access the relevant data via the appropriate domain's public interface instead and avoid adding new
          domain access violations as much as possible.
        TEXT
      end
    end

    sig { returns(String) }
    def query_details
      max_query_text_length = 2000

      query_text = if query.scrubbed_text.size > max_query_text_length
        query_start = T.must(query.scrubbed_text[0..(max_query_text_length / 2)])
        query_comment = " /* ... TRUNCATED ... */ "
        query_end = T.must(query.scrubbed_text[(max_query_text_length / 2 * -1)..-1])
        query_start + query_comment + query_end
      else
        query.scrubbed_text
      end

      <<~TEXT
        Digest: #{query.digest}
        Query:
            #{query_text}
      TEXT
    end

    sig { returns(String) }
    def tables_list
      query.tables.sort.map do |table_name|
        table_owner = tableowners.table_to_owner(table_name)
        package, level = GitHub.packageowners.package_and_ownership_level_for(table_name)
        schema_domain = GitHub::SQLCheckers::SchemaDomain.for(table_name)

        if package.present?
          "  - '#{table_name}' is owned by domain package '#{package}' and service '#{table_owner}' (table visibility level: #{level.serialize})"
        elsif table_owner.present?
          "  - '#{table_name}' is owned by service '#{table_owner}' (schema domain: '#{schema_domain}')"
        else
          "  - '#{table_name}' is unowned (schema domain: #{schema_domain})"
        end
      end.join("\n")
    end

    sig { returns(GitHub::Serviceowners::Tableowners) }
    def tableowners
      @tableowners ||= GitHub::Serviceowners::Tableowners.new
    end

    private

    sig { returns(String) }
    def test_all_features_text
      if TestEnv.test_all_features?
        "TEST_ALL_FEATURES=1 "
      else
        ""
      end
    end
  end

  at_exit do
    GitHub.packageowners.at_exit
  end
end
