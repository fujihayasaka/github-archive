# typed: true
# frozen_string_literal: true

# Encapsulates repository invitation rate limit override functionality.
#
class RepositoryInvitationRateLimitOverride

  attr_reader :repository_id

  TTL = 1.day

  def self.overridden?(repository_id)
    !!new(repository_id).overridden
  end

  def self.override!(repository_id)
    new(repository_id).override_rate_limit!
  end

  def self.override_expiration_string(repository_id)
    overridden = new(repository_id).overridden
    overridden && (Time.parse(overridden) + 24.hours).strftime("on %Y-%m-%d at %H:%M %z") || ""
  end

  def initialize(repository_id)
    @repository_id = repository_id
  end

  def limit_key
    "repositories.#{repository_id}.invitations.rate_limit_paused_at"
  end

  def override_rate_limit!
    GitHub.kv.set(limit_key, Time.zone.now.to_s, expires: TTL.from_now) # rubocop:todo GitHub/DoNotUseGlobalKv
  end

  def overridden
    GitHub.kv.get(limit_key).value! # rubocop:todo GitHub/DoNotUseGlobalKv
  end

end
