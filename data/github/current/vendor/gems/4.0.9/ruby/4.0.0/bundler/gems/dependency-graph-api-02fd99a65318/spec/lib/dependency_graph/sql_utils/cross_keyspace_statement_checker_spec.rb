# frozen_string_literal: true

require "rails_helper"
require "dependency_graph/sql_utils/cross_keyspace_statement_checker"

# Loosely based on:
# https://github.com/github/github/blob/master/test/lib/github/sql_checkers/schema_domain/statement_checker_test.rb

describe DependencyGraph::SqlUtils::CrossKeyspaceStatementChecker do
  let(:all_tables) { %w[users repositories] }
  let(:keyspace_mappings) { { "keyspace1": "users", "keyspace2": "repositories" } }

  let(:checker) { described_class.new(raise_errors: true, report_errors: true,
    all_tables: all_tables, sharded_keyspaces: keyspace_mappings)
  }
  let(:check_failure) { DependencyGraph::SqlUtils::CrossKeyspaceQueryError }
  let(:check_failure_transaction) { DependencyGraph::SqlUtils::CrossKeyspaceTransactionError }

  it "does nothing with a simple query" do
    checker.check(queries: ["SELECT * FROM users WHERE id =123"])
  end

  it "does nothing with a simple transaction" do
    checker.check(queries: [<<~SQL])
      BEGIN
      UPDATE users SET login = 'octocat' WHERE id =123
      COMMIT
    SQL
  end

  it "raises an error on a cross-keyspace join involving the repositories keyspace" do
    expect {
      checker.check(
        queries: ["SELECT users.* FROM users, repositories WHERE users.id = 123 AND repositories.id = 456"]
      )
    }.to raise_error(check_failure)

    expect {
      checker.check(queries: [<<~SQL])
        SELECT users.*
        FROM `users` INNER JOIN `repositories` AS repos
        ON `users`.`id` = repos.owner_id
        WHERE users.id = 123
      SQL
    }.to raise_error(check_failure)
  end

  it "does not raise an error if the query has been tagged as exempt" do
    checker.check(
      queries: ["SELECT users.* FROM users, repositories WHERE users.id = 123 AND repositories.id = 456 /* cross-keyspace-query-exempted */"]
    )
  end

  it "does not report when reporting is disabled" do
    Failbot.reports.clear

    checker = described_class.new(raise_errors: true, all_tables: all_tables, sharded_keyspaces: keyspace_mappings)

    expect {
      checker.check(
        queries: ["SELECT users.* FROM users, repositories WHERE users.id = 123 AND repositories.id = 456"]
      )
    }.to raise_error(check_failure)

    expect(Failbot.reports.last).to be_falsey
  end

  it "reports an error when reporting is enabled" do
    Failbot.reports.clear

    expect {
      checker.check(
        queries: ["SELECT users.* FROM users, repositories WHERE users.id = 123 AND repositories.id = 456"]
      )
    }.to raise_error(check_failure)

    expect(Failbot.exception_classname_from_hash(Failbot.reports.last)).to eq(DependencyGraph::SqlUtils::CrossKeyspaceQueryError.to_s)
  end

  it "mentions written keyspaces in error message" do
    Failbot.reports.clear

    checker = described_class.new(
      checking_transactions: true,
      report_errors: true,
      raise_errors: true,
      all_tables: all_tables, sharded_keyspaces: keyspace_mappings
    )

    expect {
      checker.check(
        queries: ["BEGIN", "INSERT INTO `users`", "UPDATE `repositories`", "COMMIT"]
      )
    }.to raise_error(check_failure_transaction)

    report = Failbot.reports.last
    expect(Failbot.exception_classname_from_hash(report)).to eq(DependencyGraph::SqlUtils::CrossKeyspaceTransactionError.to_s)
    expect(Failbot.exception_message_from_hash(report)).to include("Written to multiple keyspaces")
  end

  it "mentions written keyspaces in error message with whitespace and lower-case notation" do
    Failbot.reports.clear

    checker = described_class.new(
      checking_transactions: true,
      report_errors: true,
      raise_errors: true,
      all_tables: all_tables, sharded_keyspaces: keyspace_mappings
    )

    expect {
      checker.check(
        queries: ["BEGIN", "insert into `users` (`users.id`) SET ('1')", "    UPDATE `repositories`", "COMMIT"]
      )
    }.to raise_error(check_failure_transaction)

    report = Failbot.reports.last
    expect(Failbot.exception_classname_from_hash(report)).to eq(check_failure_transaction.to_s)
    expect(Failbot.exception_message_from_hash(report)).to include("Written to multiple keyspaces")
    expect(Failbot.exception_message_from_hash(report)).to include("insert into users (`users.id`) SET (?)")
  end

  it "does nothing with single quotes in a LIKE statement" do
    checker.check(queries: [<<~SQL])
      SELECT * FROM `topics` WHERE (`short_description` <> '') AND `name` LIKE '%languages%'
    SQL
  end

  it "never samples execution" do
    checker = described_class.new(raise_errors: true)
    queries = ["select *"]

    results = 50.times.map { checker.check(queries: queries) }

    expect(results.size).to eq(50), "expected checker to be executed exactly 50 times with no skips for sampling"
  end
end
