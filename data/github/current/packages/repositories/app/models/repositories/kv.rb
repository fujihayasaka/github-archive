# typed: strict
# frozen_string_literal: true

require_relative "kv/data_store"

module Repositories
  class Kv
    OWNER = "github/repos"

    @kv = T.let(nil, T.nilable(GitHub::KV))

    sig { returns(GitHub::KV) }
    def self.store
      return @kv if @kv

      cfg = GitHub::KV.config.dup
      cfg.table_name = Repositories::Kv::DataStore.table_name

      @kv = GitHub::KV.new(config: cfg) { ApplicationRecord::Domain::Repositories.connection }
    end
  end
end
