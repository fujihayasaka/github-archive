# typed: strict
# frozen_string_literal: true

module TradeCompliance
  class Kv

    sig { void }
    def self.initialize
      @kv = T.let(nil, T.nilable(GitHub::KV))
    end

    sig { returns(GitHub::KV) }
    def self.store
      return @kv if @kv

      config = GitHub::KV::Config.new
      config.encapsulated_errors = [
        ActiveRecord::ConnectionFailed,
        ActiveRecord::ConnectionNotEstablished,
        ActiveRecord::NoDatabaseError,
      ]
      config.table_name = :trade_compliance_key_values
      config.use_local_time = GitHub::AppEnvironment.test?
      @kv = GitHub::KV.new(config: config) { ApplicationRecord::Domain::UsersCollab.connection }
    end
  end
end
