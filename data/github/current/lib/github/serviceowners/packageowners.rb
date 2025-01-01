# typed: strict
# frozen_string_literal: true

require "digest/sha2"
require "yaml"
require "fileutils"

module GitHub
  class Serviceowners
    class Packageowners
      extend T::Sig # rubocop:todo Sorbet/RedundantExtendTSig

      # Capture fully-qualified package name given path to a file inside package
      PACKAGE_NAME_REGEX = T.let(/(packages\/\S+?)\//.freeze, Regexp)

      PACKAGE_CONFIG_FILENAME = T.let("package.yml".freeze, String)
      DOMAIN_QUERY_VIOLATIONS_FILE_NAME = T.let("domain_query_violations.yml".freeze, String)

      DOMAIN_QUERY_VIOLATIONS_FILE_HEADER = <<~YAML
        # This file is used to track queries that violate package boundaries. There are two reasons for violations:
        #
        # - Cross domain: A query uses tables from multiple domains.
        # - Domain access: A query bypassed a domain's interface and accessed its private tables directly.
        #
        # The format of this file is as follows:
        #
        # <query_digest>:
        #   query: <query>
        #   violations:
        #     - [location: <file:line>] # never committed but only generated with the --locations flag
        #       reason: <cross_domain|domain_access>
        #
        # To add a new violation, you can run the test causing the violation with the following environment variables:
        #
        #   TEST_ALL_FEATURES=1 PERFORM_STATEMENT_CHECKING=1 DOMAIN_QUERY_VIOLATIONS=1 bin/rails test <path_to_test_file>:<line_number>
        #
        # This will update the query violation file(s) with the new violation(s). To remove a violation, you can simply
        # remove the entry from the file.
        #
        # If there are many violations to add or update, or you'd like to refresh all recorded violations, you can
        # run the following command to pull all violations from the latest completed CI build on your branch:
        #
        #     script/domain-isolation-query-violations [--locations] [--audit] [--reason <cross_domain|domain_access>]
        #
        # This will replace all query violation files with the latest violations. Use the `--locations` flag to
        # include file locations in the output, don't commit that though! Use the `--audit` flag to include
        # violations from tables with visibility level `audit`. Use the `--reason` flag to filter violations
        # by reason in case you're only interested in locations for a specific reason.
      YAML

      class TableVisibilityLevel < T::Enum

        enums do
          # Enforces domain-access and cross-domain checks. Table is private to a domain and
          # should stay this way. All violations are tracked.
          Private = new

          # Enforces cross-domain and audits domain-access checks. Table is assigned to a domain
          # but is still accessible by other domains outside of the domain interface.
          # Cross-domain queries are enforced and violations tracked.
          Public = new

          # Audits domain-access and cross-domain. Table is in the process of becoming public and/or private.
          # Nothing is enforced or tracked. It provides a starting point to understand the scope and impact
          # of making a table public or private.
          Audit = new
        end

        sig { returns(T::Boolean) }
        def enforce_domain_isolation?
          self != Audit
        end
      end

      class QueryViolationReason < T::Enum

        enums do
          # Query uses tables belonging to multiple domain packages, violating domain boundaries.
          CrossDomain = new("cross_domain")

          # Query involving tables of a domain package is not issued via
          # the domain's public interface.
          DomainAccess = new("domain_access")
        end

        sig { params(coder: Psych::Coder).void }
        def encode_with(coder)
          coder.scalar = serialize
          coder.tag = nil
        end
      end

      sig { void }
      def initialize
        @package_for_type = T.let({}, T::Hash[String, T.nilable(String)])
        @owner_for_package = T.let({}, T::Hash[String, String])
        @tables_to_packages_and_levels = T.let(nil, T.nilable(T::Hash[String, [String, TableVisibilityLevel]]))
        @all_tables = T.let(nil, T.nilable(T::Set[String]))

        @stored_domain_query_violations = T.let({}, T::Hash[String, T::Hash[String, T::Hash[String, T.untyped]]])
        @recorded_domain_query_violations = T.let({}, T::Hash[String, T::Hash[String, T::Hash[String, T.untyped]]])
      end

      # Returns the package the given class/module resides in
      sig { params(type: T.any(Module, T::Class[T.anything])).returns(T.nilable(String)) }
      def package_for_type(type)
        type_name = type.to_s

        return @package_for_type[type_name] if @package_for_type.key?(type_name)

        @package_for_type[type_name] = begin
          path, _ = Object.const_source_location(type_name)
          return nil if path.nil?

          match = path.match(PACKAGE_NAME_REGEX)
          return nil if match.nil?

          match.captures.first
        end
      rescue NameError
        nil
      end

      # Returns the catalog service owner for the given package name
      sig { params(package: String).returns(String) }
      def owner_for_package(package)
        @owner_for_package[package] ||= begin
          GitHub.serviceowners&.service_for_path("#{package}/#{PACKAGE_CONFIG_FILENAME}", prefix: true) || GitHub::Serviceowners::UNKNOWN_SERVICE
        end
      end

      sig { params(table: String).returns(T.nilable(String)) }
      def package_owner_for(table)
        tables_to_packages_and_levels[table]&.first || nil
      end

      sig { params(table: String).returns([T.nilable(String), TableVisibilityLevel]) }
      def package_and_ownership_level_for(table)
        tables_to_packages_and_levels[table] || [nil, TableVisibilityLevel::Public]
      end

      sig { returns(T::Set[String]) }
      def all_tables
        return @all_tables if @all_tables
        @all_tables = tables_to_packages_and_levels.keys.to_set
      end

      sig { returns(T::Hash[String, String]) }
      def tables_to_owner
        tables_to_packages_and_levels.transform_values { |(package, _)| owner_for_package(package) }
      end

      # Only use for stubbing
      sig { returns(T::Hash[String, [String, TableVisibilityLevel]]) }
      def tables_to_packages_and_levels
        populate_tables if @tables_to_packages_and_levels.nil?
        T.must(@tables_to_packages_and_levels)
      end

      sig { params(package: String, query: String).returns(T::Array[String]) }
      def violations_for_package_and_query(package, query)
        populate_violations_for_package(package)

        query_digest = Digest::SHA256.hexdigest(query)
        violations_for(package:, query_digest:)
      end

      sig { params(package: String).void }
      def populate_violations_for_package(package)
        return if @stored_domain_query_violations.key?(package)

        path = path_for_stored_violations_artifact(package)
        return if !File.exist?(path)

        queries = YAML.safe_load_file(path)
        queries.each do |_digest, data|
          data["violations"].each do |violation|
            violation["reason"] = QueryViolationReason.deserialize(violation["reason"])
          end
        end

        @stored_domain_query_violations[package] = queries
      end

      sig { params(table: String, query: String, most_significant_frame: String, reason: QueryViolationReason).void }
      def record_violation(table, query, most_significant_frame, reason)
        package, level = package_and_ownership_level_for(table)
        return if package.nil?

        record_violation_for_package(package:, query:, tables: [table], frame: most_significant_frame, reason: reason)
      end

      sig { params(package: String, query: String, reason: QueryViolationReason).returns(T::Boolean) }
      def violation_tracked?(package, query, reason)
        violations_for_package_and_query(package, query).any? do |violation|
          # We only care and track query reasons here on purpose. The location information
          # is only collected and available via CI runs when burning down the list of violations.
          violation["reason"] == reason
        end
      end

      sig { params(frame: String, reason: QueryViolationReason).returns(T::Hash[String, String]) }
      def build_violation_for(frame, reason)
        file_with_lineno = frame.split(":")
        location = T.must(file_with_lineno[0..1]).join(":")

        { "location" => location, "reason" => reason }
      end

      sig { params(package: String, query: String, tables: T::Array[String], frame: String, reason: QueryViolationReason).void }
      def record_violation_for_package(package:, query:, tables:, frame:, reason:)
        violation = build_violation_for(frame, reason)
        query_digest = Digest::SHA256.hexdigest(query)

        @recorded_domain_query_violations[package] ||= {}
        query_data = T.must(@recorded_domain_query_violations[package])[query_digest]
        query_data ||= { "query" => query, "tables" => [], "violations" => [] }

        if !query_data["violations"].include?(violation)
          query_data["violations"] = (query_data["violations"] << violation)
        end

        if !tables.all? { |table| query_data["tables"].include?(table) }
          query_data["tables"] = (query_data["tables"] + tables).uniq.sort
        end

        T.must(@recorded_domain_query_violations[package])[query_digest] = query_data
      end

      sig { void }
      def at_exit
        return if !GitHub.record_domain_query_violations?

        in_ci = ENV["GITHUB_CI"] == "1"
        flush_package_violations(
          merge_with_stored: !in_ci,
          write_to_stored: !in_ci,
          include_locations: in_ci
        )
      end

      sig { params(merge_with_stored: T::Boolean, write_to_stored: T::Boolean, include_locations: T::Boolean).void }
      def flush_package_violations(merge_with_stored: true, write_to_stored: true, include_locations: false)
        @recorded_domain_query_violations.each do |package, recorded_queries|
          recorded_queries = recorded_queries.reject { |_, query| query["violations"].empty? }
          next if recorded_queries.empty?

          artifact_path = if write_to_stored
            path_for_stored_violations_artifact(package)
          else
            path_for_test_violations_artifact(package)
          end

          existing_queries = if merge_with_stored
            populate_violations_for_package(package)
            @stored_domain_query_violations[package]
          else
            if !write_to_stored && File.exist?(artifact_path)
              YAML.safe_load_file(artifact_path).tap do |queries|
                queries.each do |_digest, data|
                  data["violations"].each do |violation|
                    violation["reason"] = QueryViolationReason.deserialize(violation["reason"])
                  end
                end
              end
            end
          end

          queries = if existing_queries && existing_queries.present?
            merge_queries(existing_queries, recorded_queries)
          else
            recorded_queries
          end

          queries.each do |(_digest, query)|
            if !include_locations
              unique_reasons = query["violations"].each_with_object(Set.new) { |v, set| set << v["reason"] }
              query["violations"] = unique_reasons.sort.map { |reason| { "reason" => reason } }
            else
              query["violations"].sort_by! { |v| [v["location"], v["reason"]] }
            end

            query["tables"].sort!
          end
          queries = queries.sort_by { |(digest, _)| digest }

          yaml = DOMAIN_QUERY_VIOLATIONS_FILE_HEADER + "\n" + queries.to_h.to_yaml(indentation: 2)

          FileUtils.mkdir_p(File.dirname(artifact_path))
          File.write(artifact_path, yaml)
        end
      end

      sig do
        params(
          existing_queries: T::Hash[String, T::Hash[String, T.untyped]],
          recorded_queries: T::Hash[String, T::Hash[String, T.untyped]]
        ).returns(T::Hash[String, T::Hash[String, T.untyped]])
      end
      def merge_queries(existing_queries, recorded_queries)
        existing_queries.merge(recorded_queries) do |_, existing_query, recorded_query|
          recorded_query["violations"] |= existing_query["violations"] if existing_query["violations"].present?
          recorded_query["tables"] |= existing_query["tables"] if existing_query["tables"].present?
          recorded_query
        end
      end

      sig { params(tables: T::Array[String]).returns(T::Boolean) }
      def calling_package_matches_table_package?(tables)
        calling_package = GitHub::DomainIsolation.current_domain

        any_table_had_violation = T.let(false, T::Boolean)
        tables.each do |table|
          table_package = package_and_ownership_level_for(table).first
          is_violation = calling_package.nil? || calling_package != table_package

          if is_violation
            any_table_had_violation = true
            break
          end
        end

        !any_table_had_violation
      end

      sig { void }
      def populate_tables
        @tables_to_packages_and_levels = {}
        @all_tables = nil

        package_paths = Dir.glob("packages/*").select { |path| File.directory?(path) }
        package_paths.each do |package_path|
          config = YAML.safe_load_file(File.join(package_path, PACKAGE_CONFIG_FILENAME))
          tables = config.dig("metadata", "tables") || {}
          tables.each do |table, level|
            if @tables_to_packages_and_levels.key?(table)
              raise RuntimeError.new("#{table} is already defined in packages/#{@tables_to_packages_and_levels[table].first}")
            end

            package_name = package_path.to_s.scan(/packages\/[^\/]+/).first
            @tables_to_packages_and_levels[table] = [package_name, TableVisibilityLevel.deserialize(level)]
          end
        rescue Errno::ENOENT
          # skip
        end
      end

      private

      sig { params(package: String, query_digest: String).returns(T::Array[String]) }
      def violations_for(package:, query_digest:)
        @stored_domain_query_violations.dig(package, query_digest, "violations") || []
      end

      sig { params(package: String).returns(String) }
      def path_for_stored_violations_artifact(package)
        File.join(package, DOMAIN_QUERY_VIOLATIONS_FILE_NAME)
      end

      sig { params(package: String).returns(String) }
      def path_for_test_violations_artifact(package)
        dir = ENV["NON_DEPLOYABLE_ARTIFACTS_DIR"]
        path = if ENV["TEST_ENV_NUMBER"]
          File.join(dir, package, "#{ENV["TEST_ENV_NUMBER"]}-#{DOMAIN_QUERY_VIOLATIONS_FILE_NAME}")
        else
          File.join(dir, package, DOMAIN_QUERY_VIOLATIONS_FILE_NAME)
        end

        path.to_s
      end
    end
  end
end
