# typed: true
# frozen_string_literal: true

class PublicKeyAccessJob < ApplicationJob
  queue_as :public_key_accesses
  retry_on_dirty_exit

  def perform(id, unix_timestamp)
    time = Time.at(unix_timestamp)
    now = Time.now.to_i
    valid_until = unix_timestamp + PublicKey::ACCESS_THROTTLING
    ttl = valid_until - now

    # Only set the memcached lock if the ttl would be greater than 0. 0 is
    # default ttl and means forever, which we don't want. Less than zero
    # means the key would be of no use.
    if ttl > 0
      return unless GitHub.cache.add(self.class.write_prevention_cache_key(id), time, ttl)
    end

    if public_key = PublicKey.find_by(id: id)
      public_key.access!(time)
    end
  end

  def self.write_prevention_cache_key(id)
    "github:jobs:public_key_access:#{id}"
  end
end
