# typed: strict
# frozen_string_literal: true

require_relative "k_v/data_store"

module SparkRuntime
  class KV
    OWNER = "github/copilot-workbench"

    @kv = T.let(nil, T.nilable(GitHub::KV))

    sig { returns(GitHub::KV) }
    def self.store
      return @kv if @kv

      config = GitHub::KV.config.dup
      config.table_name = SparkRuntime::KV::DataStore.table_name

      @kv = GitHub::KV.new(config: config) { ApplicationRecord::Domain::Copilot.connection }
    end
  end
end
