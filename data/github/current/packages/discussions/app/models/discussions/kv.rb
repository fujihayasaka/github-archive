# typed: strict
# frozen_string_literal: true

module Discussions
  class Kv
    extend T::Sig
    OWNER = "github/discussions"

    @kv = T.let(nil, T.nilable(GitHub::KV))

    sig { returns(GitHub::KV) }
    def self.store
      return @kv if @kv

      cfg = GitHub::KV.config.dup
      cfg.table_name = Discussions::Kv::DataStore.table_name

      @kv = GitHub::KV.new(config: cfg) { ApplicationRecord::Domain::Discussions.connection }
    end
  end
end
