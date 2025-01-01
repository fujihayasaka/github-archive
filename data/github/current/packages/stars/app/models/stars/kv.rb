# typed: strict
# frozen_string_literal: true

require "github/config/kv_dual_write"

module Stars
  class Kv

    OWNER = "github/star"

    @kv = T.let(nil, T.nilable(GitHub::KV))

    sig { returns(GitHub::KV) }
    def self.store
      @kv ||= begin
                cfg = GitHub::KV.config.dup
                cfg.table_name = Stars::Kv::DataStore.table_name

                GitHub::KV.new(config: cfg) { ApplicationRecord::Domain::Users.connection }
              end
    end
  end
end
