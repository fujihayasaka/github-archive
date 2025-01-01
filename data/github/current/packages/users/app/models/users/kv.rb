# typed: strict
# frozen_string_literal: true

module Users
  class Kv
    extend T::Sig
    @kv = T.let(nil, T.nilable(GitHub::KV))

    sig { returns(GitHub::KV) }
    def self.store
      @kv ||= begin
                cfg = GitHub::KV.config.dup
                cfg.table_name = Users::Kv::DataStore.table_name

                GitHub::KV.new(config: cfg) { ApplicationRecord::Domain::Users.connection }
              end
    end
  end
end
