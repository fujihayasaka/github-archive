# typed: strict
# frozen_string_literal: true

module Codespaces
  class Kv

    sig { void }
    def self.initialize
      @kv = T.let(nil, T.nilable(GitHub::KV))
    end

    sig { returns(GitHub::KV) }
    def self.store
      return @kv if @kv

      # this will be the remaining implementation once the migration is complete
      cfg = GitHub::KV.config.dup
      cfg.table_name = :codespaces_key_values
      @kv = GitHub::KV.new(config: cfg) { ApplicationRecord::Domain::Codespaces.connection }
      @kv
    end
  end
end
