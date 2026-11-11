# typed: strict
# frozen_string_literal: true

require_relative "../../models/code_scanning/k_v/data_store"

module CodeScanning
  class KV
    OWNER = "github/code_scanning"

    @kv = T.let(nil, T.nilable(GitHub::KV))

    sig { returns(GitHub::KV) }
    def self.store
      return @kv if @kv

      config = GitHub::KV.config.dup
      config.table_name = CodeScanning::KV::DataStore.table_name

      @kv = GitHub::KV.new(config:) { ApplicationRecord::Domain::RepositoriesNotify.connection }
    end
  end
end
