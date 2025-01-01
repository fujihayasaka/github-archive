# typed: strict
# frozen_string_literal: true

require "github/config/kv_dual_write"
require_relative "kv/data_store"

module FeatureManagement
  class Kv
    extend T::Sig

    @kv = T.let(nil, T.nilable(GitHub::KV))

    sig { returns(GitHub::KV) }
    def self.store
      return @kv if @kv

      cfg = GitHub::KV.config.dup
      cfg.table_name = FeatureManagement::Kv::DataStore.table_name

      @kv = GitHub::KV.new(config: cfg) { FeatureManagement::Kv::DataStore.connection }
    end
  end
end
