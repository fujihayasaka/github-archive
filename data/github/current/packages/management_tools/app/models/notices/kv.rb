# typed: strict
# frozen_string_literal: true

module Notices
  class Kv

    @kv = T.let(nil, T.nilable(GitHub::KV))

    sig { returns(GitHub::KV) }
    def self.store
      @kv ||= begin

                cfg = GitHub::KV.config.dup
                cfg.table_name = Notices::Kv::DataStore.table_name

                GitHub::KV.new(config: cfg) { ApplicationRecord::Domain::FeatureManagement.connection }
              end
    end
  end
end
