# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strict
# frozen_string_literal: true

class OauthAccessBumpJob < ApplicationJob
  queue_as :oauth_access_bumps
  retry_on_dirty_exit

  # Resolving the tenant context is not strictly needed for this job,
  # because it only updates a timestamp on the access.
  #
  # However, it's a good idea to resolve the tenant context anyway for
  # the sake of consistency or if we ever decide to add more logic to
  # this job.
  resolve_tenant_context do |id, _|
    user = OauthAccessTokens.domain.by_id(id)&.user
    T.cast(user, User).enterprise_managed_business if user
  end

  sig { params(id: Integer, unix_timestamp: Integer).void }
  def perform(id, unix_timestamp)
    time = Time.at(unix_timestamp)
    now = Time.now.to_i
    valid_until = unix_timestamp + OauthAccess::ACCESS_THROTTLING
    ttl = valid_until - now

    # Only set the memcached lock if the ttl would be greater than 0. 0 is
    # default ttl and means forever, which we don't want. Less than zero
    # means the key would be of no use.
    if ttl > 0
      return unless GitHub.cache.add(write_prevention_cache_key(id), time, ttl)
    end

    if oauth_access = OauthAccess.find_by(id: id)
      oauth_access.bump!(time)
    end
  end

  private

  sig { params(id: Integer).returns(String) }
  def write_prevention_cache_key(id)
    "github:jobs:oauth_access_bump:#{id}"
  end
end
