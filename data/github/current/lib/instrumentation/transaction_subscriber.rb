# typed: true
# frozen_string_literal: true

# Instrumentation meant to check for SQL transactions.
# Checks each SQL statement with a transaction, including nested transactions if they
# are present.
#
# In the test environment, the subscriber presumes each test runs in a top-level
# transaction and only checks the nested transactions it contains.
#
module Instrumentation
  class TransactionSubscriber
    attr_reader :ignore_top_level_transaction

    def initialize(checkers: [], ignore_top_level_transaction: Rails.env.test?)
      @ignore_top_level_transaction = ignore_top_level_transaction
      @checkers = checkers
    end

    def call(event, start, ending, notifier_id, payload)
      return unless GitHub.flipper[:report_cross_domain_transactions].enabled?
      return unless @checkers.size > 0

      select_transaction_statements(payload[:queries]).each do |queries|
        @checkers.each do |checker|
          checker.check(queries: queries)
        end
      end
    end

    private

    def select_transaction_statements(queries)
      statements = queries.map { |query| query[:sql] }

      return [statements] unless ignore_top_level_transaction

      nested_transactions = []
      this_transaction = []
      savepoints_seen = 0
      releases_seen = 0
      statements.each do |stmnt|
        if stmnt =~ /(?<!RELEASE )\bSAVEPOINT\b/i
          savepoints_seen += 1
        end
        if stmnt =~ /\bRELEASE SAVEPOINT\b/i
          releases_seen += 1
        end
        if savepoints_seen > 0
          this_transaction << stmnt
        end
        if releases_seen > savepoints_seen
          raise RuntimeError.new("Mismatch in SAVEPOINT statements and RELEASE statements:\n\n#{statements.join("\n")}")
        end
        if savepoints_seen > 0 && savepoints_seen == releases_seen
          nested_transactions << this_transaction
          this_transaction = []
          savepoints_seen = 0
          releases_seen = 0
        end
      end

      nested_transactions
    end
  end
end
