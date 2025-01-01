# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class KV
      sig { returns(GitHub::KV) }
      def self.store
        return @kv if @kv

        config = GitHub::KV::Config.new
        config.encapsulated_errors = [
          ActiveRecord::ConnectionFailed,
          ActiveRecord::ConnectionNotEstablished,
          ActiveRecord::NoDatabaseError,
        ]
        config.table_name = :migrations_key_values
        config.use_local_time = GitHub::AppEnvironment.test?
        @kv = GitHub::KV.new(config: config) { ApplicationRecord::Domain::Migrations.connection }
      end
    end
  end
end
