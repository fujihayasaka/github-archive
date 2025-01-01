# typed: true
# frozen_string_literal: true

module SecurityProductsEnablement
  class KV
    extend T::Sig

    sig { returns(GitHub::KV) }
    def self.store
      @store ||= T.let(build_store, T.nilable(GitHub::KV))
    end

    sig { returns(GitHub::KV) }
    def self.build_store
      config = GitHub::KV.config.dup
      config.table_name = :security_products_enablement_key_values
      GitHub::KV.new(config:) { ApplicationRecord::Domain::RepositoriesNotify.connection }
    end

    # Create helper methods so we can call `SecurityProductsEnablement::KV.get`
    #   instead of `SecurityProductsEnablement::KV.store.get`
    #
    sig { params(key: String).void }
    def self.del(key) = self.store.del(key)

    sig { params(key: String).returns(GitHub::KV::Result) }
    def self.exists(key) = self.store.exists(key)

    sig { params(key: String).returns(GitHub::KV::Result) }
    def self.get(key) = self.store.get(key)

    sig { params(key: String, amount: Integer, expires: T.nilable(Time)).returns(Integer) }
    def self.increment(key, amount: 1, expires: nil) = self.store.increment(key, amount:, expires:)

    sig { params(key: String, value: String, expires: T.nilable(Time)).void }
    def self.set(key, value, expires: nil) = self.store.set(key, value, expires:)

    sig { params(key: String, value: String, expires: T.nilable(Time)).returns(T::Boolean) }
    def self.setnx(key, value, expires: nil) = self.store.setnx(key, value, expires:)

    sig { params(key: String).returns(GitHub::KV::Result) }
    def self.ttl(key) = self.store.ttl(key)

    sig { params(keys: T::Array[String]).void }
    def self.mdel(keys) = self.store.mdel(keys)

    sig { params(keys: T::Array[String]).returns(GitHub::Result) }
    def self.mexists(keys) = self.store.mexists(keys)

    sig { params(keys: T::Array[String]).returns(GitHub::Result) }
    def self.mget(keys) = self.store.mget(keys)

    sig { params(kvs: T::Hash[String, String], expires: T.nilable(Time)).void }
    def self.mset(kvs, expires: nil) = self.store.mset(kvs, expires:)

    sig { params(keys: T::Array[String]).returns(GitHub::KV::Result) }
    def self.mttl(keys) = self.store.mttl(keys)
  end
end
