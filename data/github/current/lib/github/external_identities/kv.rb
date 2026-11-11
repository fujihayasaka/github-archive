# typed: strict
# frozen_string_literal: true

require "github/config/kv_dual_write"

module ExternalIdentities
  class KV
    class DataStore < ApplicationRecord::Domain::Users
      self.table_name = "external_identities_key_values"
    end

    OWNER = "github/external_identities"

    @kv = T.let(nil, T.nilable(GitHub::KV))

    sig { returns(GitHub::KV) }
    def self.store
      return @kv if @kv

      config = GitHub::KV.config.dup
      config.table_name = ExternalIdentities::KV::DataStore.table_name
      local_kv = GitHub::KV.new(config: config) { ApplicationRecord::Domain::Users.connection }

      @kv = local_kv
    end

    sig { params(key: String, value: String, expires: T.nilable(Time)).void }
    def self.set(key, value, expires: nil)
      if expires.present?
        now = Time.current
        # taking care of the DST change from 2am to 1am
        # During DST change in November, if the current time is between 1am and 2am and the expiration time is after 2am,
        # we need to add an extra hour to the expiration time to make sure the cache is not immediately expired.
        # For example, if the current time is 1:30am and the expiration time is 2:00am, the cache will be immediately expired,
        # if we did not add an extra hour to the expiration time.
        # In this case, we need to add an extra hour to the expiration time to make sure the cache is not immediately expired.
        # The logic checks the expiration time hour is the same as the current hour, in which case the expiration time is updated
        # only if the utc offsets are different between the current time and the expiration time.
        # For example, current time offset -7 vs expires time offset -8.
        if now.hour == expires.hour && now.utc_offset > expires.utc_offset
          expires += 1.hour
        end
      end

      store.set(key, value, expires: expires)
    end

    sig { params(key: String).returns(GitHub::KV::Result) }
    def self.get(key)
      store.get(key)
    end

    sig { params(key: String).void }
    def self.del(key)
      store.del(key)
    end

    sig { params(key: String).returns(GitHub::KV::Result) }
    def self.ttl(key)
      store.ttl(key)
    end

    sig { params(key: String).returns(GitHub::KV::Result) }
    def self.exists(key)
      store.exists(key)
    end

    sig { returns(ActiveRecord::ConnectionAdapters::TrilogyAdapter) }
    def self.connection
      store.connection
    end
  end
end
