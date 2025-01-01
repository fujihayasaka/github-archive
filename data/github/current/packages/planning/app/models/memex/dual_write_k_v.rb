# typed: strict
# frozen_string_literal: true

require "github/config/kv_dual_write"

module Memex
  class DualWriteKV
    OWNER = "github/memex"

    sig { returns(GitHub::Config::DualWriteKV) }
    def self.store
      @store ||= T.let(build_store, T.nilable(GitHub::Config::DualWriteKV))
    end

    sig { returns(GitHub::Config::DualWriteKV) }
    def self.build_store
      kv_source = GitHub.kv # rubocop:todo GitHub/DoNotUseGlobalKv
      kv_target = Memex::KV.store

      flags = GitHub::Config::DualWriteKV::Flags.with_prefix(:memex)
      GitHub::Config::DualWriteKV.new(owner: OWNER, kv_source:, kv_target:, flags:)
    end
  end
end
