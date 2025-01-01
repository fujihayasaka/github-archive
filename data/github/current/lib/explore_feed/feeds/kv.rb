# typed: true
# frozen_string_literal: true

require "github/config/kv_dual_write"
require "explore_feed/feeds/kv/data_store"

module Feeds
  class KV
    OWNER = "github/feeds"

    sig { returns(GitHub::KV) }
    def self.store
      return @kv if @kv

      config = GitHub::KV::Config.new
      config.encapsulated_errors = [
        ActiveRecord::ConnectionFailed,
        ActiveRecord::ConnectionNotEstablished,
        ActiveRecord::NoDatabaseError,
      ]
      config.table_name = Feeds::KV::DataStore.table_name
      config.use_local_time = GitHub::AppEnvironment.test?

      @kv = GitHub::KV.new(config: config) { ApplicationRecord::Domain::UsersBallast.connection }
    end
  end
end
