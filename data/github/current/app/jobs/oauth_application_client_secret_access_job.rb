# typed: strict
# frozen_string_literal: true

class OauthApplicationClientSecretAccessJob < ApplicationJob
  extend T::Sig

  queue_as :oauth_application_client_secret_accesses
  retry_on_dirty_exit

  # Resolving the tenant context is not strictly needed for this job,
  # because it only updates a timestamp on the client-secret.
  #
  # However, it's a good idea to resolve the tenant context anyway for
  # the sake of consistency or if we ever decide to add more logic to
  # this job.
  resolve_tenant_context do |id, _|
    OauthApplicationClientSecret.find_by(id: id)&.creator&.enterprise_managed_business
  end

  sig { params(id: Integer, unix_timestamp: Integer).void }
  def perform(id, unix_timestamp)
    time = Time.at(unix_timestamp)
    now = Time.now.to_i
    valid_until = unix_timestamp + OauthApplicationClientSecret::ACCESS_THROTTLING
    ttl = valid_until - now

    # Only set the memcached lock if the ttl would be greater than 0. 0 is
    # default ttl and means forever, which we don't want. Less than zero
    # means the key would be of no use.
    if ttl > 0
      return unless GitHub.cache.add(self.class.write_prevention_cache_key(id), time, ttl)
    end

    if oauth_application_client_secret = OauthApplicationClientSecret.find_by(id: id)
      oauth_application_client_secret.access!(time)
    end
  end

  sig { params(id: Integer).returns(String) }
  def self.write_prevention_cache_key(id)
    "github:jobs:oauth_application_client_secret_access:#{id}"
  end
end
