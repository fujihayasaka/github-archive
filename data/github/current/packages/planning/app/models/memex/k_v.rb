# typed: strict
# frozen_string_literal: true

module Memex
  class KV

    sig { returns(GitHub::KV) }
    def self.store
      @store ||= T.let(build_store, T.nilable(GitHub::KV))
    end

    sig { returns(GitHub::KV) }
    def self.build_store
      config = GitHub::KV::Config.new
      config.encapsulated_errors = [
        ActiveRecord::ConnectionFailed,
        ActiveRecord::ConnectionNotEstablished,
        ActiveRecord::NoDatabaseError,
      ]
      config.table_name = :memex_key_values
      config.use_local_time = GitHub::AppEnvironment.test?

      GitHub::KV.new(config: config) do
        ApplicationRecord::Domain::Memexes.connection
      end
    end
  end
end
