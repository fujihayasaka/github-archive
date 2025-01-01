# typed: strict
# frozen_string_literal: true

class OauthAuthorizationBumpJob < ApplicationJob
  queue_as :oauth_authorization_bumps

  retry_on_dirty_exit

  # Resolving the tenant context is not strictly needed for this job,
  # because it only updates a timestamp on the authorization.
  #
  # However, it's a good idea to resolve the tenant context anyway for
  # the sake of consistency or if we ever decide to add more logic to
  # this job.
  resolve_tenant_context do |id, _|
    OauthAuthorization.find_by(id: id)&.user&.enterprise_managed_business
  end

  sig { params(id: Integer, unix_timestamp: Integer).void }
  def perform(id, unix_timestamp)
    time = Time.at(unix_timestamp)
    now = Time.now.to_i
    valid_until = unix_timestamp + OauthAuthorization::ACCESS_THROTTLING
    ttl = valid_until - now

    # Only set the memcached lock if the ttl would be greater than 0. 0 is
    # default ttl and means forever, which we don't want. Less than zero
    # means the key would be of no use.
    if ttl > 0
      return unless GitHub.cache.add(write_prevention_cache_key(id), time, ttl)
    end

    bump_finished = T.let(false, T::Boolean)
    begin
      if oauth_authorization = OauthAuthorization.find_by(id: id)
        oauth_authorization.bump!(time)
        bump_finished = true
      end
    ensure
      GitHub.cache.delete(write_prevention_cache_key(id)) unless bump_finished
    end
  end

  sig { params(id: Integer).returns(String) }
  def write_prevention_cache_key(id)
    "github:jobs:oauth_authorization_bump:#{id}"
  end
end
