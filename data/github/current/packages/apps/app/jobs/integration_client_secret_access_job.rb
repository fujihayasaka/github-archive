# typed: true
# frozen_string_literal: true

class IntegrationClientSecretAccessJob < ApplicationJob
  queue_as :integration_client_secret_accesses
  retry_on_dirty_exit

  def perform(id, unix_timestamp)
    time = Time.at(unix_timestamp)
    now = Time.now.to_i
    valid_until = unix_timestamp + IntegrationClientSecret::ACCESS_THROTTLING
    ttl = valid_until - now

    # Only set the memcached lock if the ttl would be greater than 0. 0 is
    # default ttl and means forever, which we don't want. Less than zero
    # means the key would be of no use.
    if ttl > 0
      return unless GitHub.cache.add(self.class.write_prevention_cache_key(id), time, ttl)
    end

    if integration_client_secret = IntegrationClientSecret.find_by(id: id)
      integration_client_secret.access!(time)
    end
  end

  def self.write_prevention_cache_key(id)
    "github:jobs:integration_client_secret_access:#{id}"
  end
end
