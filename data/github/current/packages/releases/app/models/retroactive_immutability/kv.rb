# typed: strict
# frozen_string_literal: true

module RetroactiveImmutability
  class Kv
    @kv = T.let(nil, T.nilable(GitHub::KV))

    sig { returns(GitHub::KV) }
    def self.store
      return @kv if @kv

      cfg = GitHub::KV.config.dup
      cfg.table_name = "repositories_key_values"
      @kv = GitHub::KV.new(config: cfg) { ApplicationRecord::Domain::Repositories.connection }
    end
  end
end
