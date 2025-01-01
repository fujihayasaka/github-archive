# typed: strict
# frozen_string_literal: true

require "github/config/kv_dual_write"
require_relative "k_v/data_store"

module Mobile
  class KV
    OWNER = "github/client_apps_platform"

    @kv = T.let(nil, T.nilable(GitHub::KV))

    sig { returns(GitHub::KV) }
    def self.store
      return @kv if @kv

      config = GitHub::KV.config.dup
      config.table_name = Mobile::KV::DataStore.table_name

      @kv = GitHub::KV.new(config:) { ApplicationRecord::Domain::UsersCollab.connection }
    end
  end
end
