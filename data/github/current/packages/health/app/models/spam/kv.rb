# typed: strict
# frozen_string_literal: true

module Spam
  class Kv
    extend T::Sig

    sig { void }
    def self.initialize
      @kv = T.let(nil, T.nilable(GitHub::KV))
    end

    sig { returns(GitHub::KV) }
    def self.store
      return @kv if @kv

      cfg = GitHub::KV.config.dup
      cfg.table_name = :spam_key_values
      @kv = GitHub::KV.new(config: cfg) { ApplicationRecord::Domain::Spam.connection }
    end
  end
end
