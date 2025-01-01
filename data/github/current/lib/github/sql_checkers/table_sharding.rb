# typed: true
# frozen_string_literal: true

module GitHub::SQLCheckers::TableSharding
  # These are only raised in dev and should always blow through
  # catchall rescues, hence the inheritence from Exception.
  class CrossShardQueryError < Exception; end

  def self.allowing_cross_shard_queries(&block)
    ActiveSupport::ExecutionContext.set("cross-shard-query-exempted": true, &block)
  end
end

require "github/sql_checkers/table_sharding/statement_checker"
