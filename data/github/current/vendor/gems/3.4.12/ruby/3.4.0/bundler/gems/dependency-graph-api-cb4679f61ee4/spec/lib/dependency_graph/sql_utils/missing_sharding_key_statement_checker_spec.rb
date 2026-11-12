# frozen_string_literal: true

require "rails_helper"
require "dependency_graph/sql_utils/sharding_key_missing_statement_checker"

# Adapted from:
# https://github.com/github/github/blob/master/test/lib/github/sql_checkers/table_sharding/statement_checker_test.rb

describe DependencyGraph::SqlUtils::ShardingKeyMissingStatementChecker do

  let(:checker) { described_class.new(raise_errors: true, report_errors: true) }
  let(:check_failure) { DependencyGraph::SqlUtils::QueryWithoutShardingKeyError }

  before do
    stub_const("DependencyGraph::SqlUtils::ShardingKeyMissingStatementChecker::INCLUDED_TABLES", {
      "statuses" => { sharding_key: "repository_id" }
    })
  end

  context "read queries" do
    it "does nothing with a simple query containing sharding key" do
      checker.check(
        queries: ["SELECT * FROM `statuses` WHERE `statuses`.`id` = 123 AND `statuses`.`repository_id` = 456"]
      )

      checker.check(
        queries: [<<~SQL],
          SELECT *
          FROM statuses
          WHERE statuses.id = 123
          AND statuses.repository_id = 456
        SQL
      )
    end

    it "does nothing with a simple query containing sharding key without specifying table" do
      checker.check(
        queries: ["SELECT * FROM statuses WHERE id = 123 AND repository_id = 456"]
      )
    end

    it "does nothing with a simple query containing primary key" do
      checker.check(
        queries: ["SELECT * FROM `statuses` WHERE `statuses`.`id` = 123"]
      )
    end

    it "does nothing with a simple query containing primary key without specifying table" do
      checker.check(
        queries: ["SELECT * FROM statuses WHERE id = 123"]
      )
    end

    it "raises an error for a cross-shard query" do
      expect {
        checker.check(
          queries: ["SELECT * FROM `statuses` WHERE `statuses`.`creator_id` = 10"]
        )
      }.to raise_error(check_failure)
    end

    it "raises an error for a cross-shard query with primary key list" do
      expect {
        checker.check(
          queries: ["SELECT * FROM `statuses` WHERE `id` IN (123, 456, 789)"]
        )
      }.to raise_error(check_failure)
    end

    it "does nothing with a query with primary key list containing sharding key" do
      checker.check(
        queries: ["SELECT * FROM `statuses` WHERE `id` IN (123, 456, 789) AND `repository_id` = 5"]
      )
    end

    it "recognizes table aliases in simple query" do
      checker.check(
        queries: ["SELECT * FROM statuses s WHERE s.id = 5 AND s.repository_id = 5"]
      )
    end

    it "does nothing with a query containing a join statement with sharding key" do
      stub_const("DependencyGraph::SqlUtils::ShardingKeyMissingStatementChecker::INCLUDED_TABLES", {
        "statuses" => { sharding_key: "repository_id" }, "sub_statuses" => { sharding_key: "repository_id" }
      })
      described_class.new(raise_errors: true, report_errors: true).check(
        queries: [<<~SQL],
          SELECT * FROM statuses
          INNER JOIN sub_statuses ON statuses.id = sub_statuses.status_id
            AND statuses.repository_id = sub_statuses.repository_id -- this clause is required
          WHERE statuses.repository_id = 5 AND sub_statuses.state = 0
        SQL
      )

      described_class.new(raise_errors: true, report_errors: true).check(
        queries: [<<~SQL],
          SELECT * FROM statuses
          INNER JOIN sub_statuses ON statuses.id = sub_statuses.status_id
            AND sub_statuses.repository_id = statuses.repository_id -- this clause is flipped
          WHERE statuses.repository_id = 5 AND sub_statuses.state = 0
        SQL
      )
    end

    it "raises error for a query containing a join statement without sharding key" do
      stub_const("DependencyGraph::SqlUtils::ShardingKeyMissingStatementChecker::INCLUDED_TABLES", {
        "statuses" => { sharding_key: "repository_id" }, "sub_statuses" => { sharding_key: "repository_id" }
      })
      expect {
        described_class.new(raise_errors: true, report_errors: true).check(
          queries: [<<~SQL],
            SELECT * FROM statuses
            INNER JOIN sub_statuses ON statuses.id = sub_statuses.status_id -- repository_id clause missing here
            WHERE statuses.repository_id = 5 AND sub_statuses.state = 0
          SQL
        )
      }.to raise_error(check_failure)
    end
  end

  context "write queries" do
    it "does nothing with insert queries" do
      checker.check(
        queries: ["INSERT INTO statuses (repository_id, github_app_id, creator_id) VALUES (1, 2, 3)"]
      )
    end

    it "does nothing for update queries that contain primary key" do
      checker.check(
        queries: ["UPDATE statuses SET creator_id = 1 WHERE id = 2"]
      )
    end

    it "raises for update queries that contain primary key list" do
      expect {
        checker.check(
          queries: ["UPDATE statuses SET creator_id = 1 WHERE id IN (1, 2, 3, 4)"]
        )
      }.to raise_error(check_failure)
    end

    it "does nothing for delete queries that contain primary key" do
      checker.check(
        queries: ["DELETE FROM statuses WHERE id = 2"]
      )
    end

    it "raises for delete queries that contain primary key list" do
      expect {
        checker.check(
          queries: ["DELETE FROM statuses WHERE id IN (2, 3, 4, 5)"]
        )
      }.to raise_error(check_failure)
    end
  end
end
