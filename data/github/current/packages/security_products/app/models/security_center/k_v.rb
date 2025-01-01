# typed: strict
# frozen_string_literal: true

require "github/config/kv_dual_write"

module SecurityCenter
  class KV
    extend T::Sig
    OWNER = "github/security-center"

    @kv = T.let(nil, T.nilable(GitHub::KV))

    sig { returns(GitHub::KV) }
    def self.store
      return @kv if @kv

      config = GitHub::KV::Config.new
      config.encapsulated_errors = [
        ActiveRecord::ConnectionFailed,
        ActiveRecord::ConnectionNotEstablished,
        ActiveRecord::NoDatabaseError,
      ]
      config.table_name = SecurityCenter::KV::DataStore.table_name
      config.use_local_time = GitHub::AppEnvironment.test?

      @kv = GitHub::KV.new(config: config) { ApplicationRecord::Domain::SecurityOverviewAnalytics.connection }
    end
  end
end
