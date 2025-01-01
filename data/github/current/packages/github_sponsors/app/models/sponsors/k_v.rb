# typed: strict
# frozen_string_literal: true

require "github/config/kv_dual_write"
require_relative "k_v/data_store"

module Sponsors
  class KV
    extend T::Sig # rubocop:todo Sorbet/RedundantExtendTSig
    OWNER = "github/sponsors"

    @kv = T.let(nil, T.nilable(GitHub::KV))

    sig { returns(GitHub::KV) }
    def self.store
      return @kv if @kv

      config = GitHub::KV.config.dup
      config.table_name = Sponsors::KV::DataStore.table_name

      @kv = GitHub::KV.new(config: config) { ApplicationRecord::Domain::Sponsors.connection }
    end
  end
end
