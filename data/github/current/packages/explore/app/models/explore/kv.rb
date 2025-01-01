# typed: strict
# frozen_string_literal: true

require "github/config/kv_dual_write"

module Explore
  class Kv
    OWNER = "github/explore"

    @kv = T.let(nil, T.nilable(GitHub::KV))

    sig { returns(GitHub::KV) }
    def self.store
      @kv ||= begin
                cfg = GitHub::KV.config.dup
                cfg.table_name = Explore::Kv::DataStore.table_name

                GitHub::KV.new(config: cfg) { ApplicationRecord::Domain::Explore.connection }
              end
    end
  end
end
