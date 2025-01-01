# typed: true
# frozen_string_literal: true

# AuthenticationLimits are instantiated in
# /config/authentication_limits.rb
class AuthenticationLimit
  include Instrumentation::Model

  DEVICE_LOGIN_LOCKOUT_KEYS = if GitHub.sign_in_analysis_enabled?
    %i(verified_device_login device_creation_login device_use_login)
  end

  LOGIN_LOCKOUT_KEYS = %i(
    login
    two_factor_login
    password_reset_login
    email_verification_login
    change_password_login
    sms_2fa_setup_by_login
    sms_2fa_setup_spammy_ip_secondary_limit_by_login
  ) + Array(DEVICE_LOGIN_LOCKOUT_KEYS)

  class << self
    attr_accessor :instances
  end
  @instances = []

  attr_reader :name, :data_key, :max_tries

  def initialize(name:, max_tries:, ttl:, data_key:, ban_ttl: nil, whitelist_key: nil)
    @name = name
    @max_tries = max_tries
    @ttl = ttl
    @data_key = data_key
    @ban_ttl = ban_ttl
    @whitelist_key = whitelist_key || data_key

    self.class.instances << self
  end

  # Check various auth limits.
  #
  # data      - Rate limit options and values to check against any auth limits.
  #             :ip - Remote IP address of the login attempt (optional).
  #             :login, two_factor_login, verified_device_login, device_creation_login, device_use_login
  #               - The login of the user attempting to auth (optional).
  # increment - If increment is false, return true as soon as we discover we're
  #   at any limit. If increment is true, iterate over every limiter to ensure
  #   all relevant counts are bumped.
  # from      - the source of the inquiry (used for stats and audit log)
  # actor_ip  - the IP address of the request (used for the audit log when
  #   data_keys doesn't contain an IP).
  #
  # Returns true if any of the rate limits have been met.
  def self.at_any?(increment: false, from: :web, actor_ip: nil, **data)
    at_any = false

    instances.reduce(false) do |at_any, instance|
      at = instance.at?(increment: increment, from: from, actor_ip: actor_ip, **data)
      return true if at && !increment
      at_any || at
    end
  end

  # returns names of limits with active lockouts
  def self.get_active_lockouts(data)
    instances.map { |i| i.name if i.at?(**data) }.compact
  end

  # Check various auth limits.
  #
  # data      - Rate limit options and values to check against any auth limits.
  #             :ip - Remote IP address of the login attempt (optional).
  #             :login, two_factor_login, verified_device_login, device_creation_login, device_use_login
  #               - The login of the user attempting to auth (optional).
  # increment - If increment is false, return true as soon as we discover we're
  #   at any limit. If increment is true, iterate over every limiter to ensure
  #   all relevant counts are bumped before returning.
  # from      - the source of the inquiry (used for stats and audit log)
  # actor_ip  - the IP address of the request (used for the audit log when
  #   data_keys doesn't contain an IP).
  #
  # Returns true if the rate limit value has been met.
  def at?(increment: false, from: :web, actor_ip: nil, **data)
    return false unless value = data[data_key]

    over_before_increment = at_rate_limit?(value, false)

    # Return fast if we're not incrementing or we're over the limit.
    if over_before_increment || !increment
      return over_before_increment && !whitelisted?(value)
    end

    over_after_increment = at_rate_limit?(value, true)

    # Check whitelist if over limit.
    return false if over_after_increment && whitelisted?(value)

    # We only instrument if the limit has just been exceeded.
    instrument_lockout(**T.unsafe({ from: from, actor_ip: actor_ip, **data })) if over_after_increment
    over_after_increment
  end

  def self.user(data)
    User.find_by_login_or_email(login(data))
  end

  def self.login(data)
    data.values_at(*LOGIN_LOCKOUT_KEYS).compact.first
  end

  # Clear the auth limit data associated with keys/values.
  #
  # data - Values to remove auth limit data for.
  #        :ip    - Remote IP address of the login attempt (optional).
  #        :login - The login of the user attempting to auth (optional).
  #
  # Returns nothing
  def self.clear_data(data)
    instances.each { |i| i.clear_data(data) }
  end

  # Convenience method for taking a given login and producing a hash
  # of all possible key/value pairs for limiters that use a login
  def self.all_data_for_login(login)
    Hash[LOGIN_LOCKOUT_KEYS.map { |key| [key, login] }]
  end

  # Clear the auth limit data associated with keys/values.
  #
  # data - Values to remove auth limit data for.
  #        :ip    - Remote IP address of the login attempt (optional).
  #        :login - The login of the user attempting to auth (optional).
  #
  # Returns nothing
  def clear_data(data)
    return unless value = data[data_key]
    over_limit = at_rate_limit?(value, false)

    GitHub.dogstats.increment("authn_kv", tags: ["action:delete", "callsite:authentication_limit"])
    GitHub::Authentication::KV.store.del(rate_limit_key(value))

    # audit log only when an active lockout is being cleared
    instrument_remove(self.class.user(data)) if over_limit
  end

  # Check the various rate limits and return the longest expiration.
  #
  # data - Values to check against auth limits.
  #        :ip    - Remote IP address of the login attempt (optional).
  #        :login - The login of the user attempting to auth (optional).
  #
  # Returns Time object of the longest expiration or nil if there is no
  # expiration.
  def self.longest_expiration(data)
    instances.map { |i| i.expiration(data) }.compact.max
  end

  # Check the rate limit associated with the given key/value and return the
  # expiration.
  #
  # data - Values to check against rate limit.
  #        :ip    - Remote IP address of the login attempt (optional).
  #        :login - The login of the user attempting to auth (optional).
  #
  # Returns Time object of the expiration or nil if there is no expiration.
  def expiration(data)
    return unless value = data[data_key]
    return nil unless at_rate_limit?(value, false)
    GitHub.dogstats.increment("authn_kv", tags: ["action:read", "callsite:authentication_limit"])
    str_value = GitHub::Authentication::KV.store.ttl(rate_limit_key(value)).value do |error|
      Failbot.report(error)
      return nil
    end

    Time.at(str_value.to_i)
  end

  private

  # Check RateLimiter to see if the given value is over the rate limit for this
  # auth limit.
  #
  # key       - The value used as the base of a limiter key.
  # increment - Should RateLimiter increment its key.
  #
  # Returns true if the rate limit has been met, false otherwise.
  def at_rate_limit?(key, increment)
    tries = if increment
      begin
        limit = ActiveRecord::Base.connected_to(role: :writing) do
          GitHub.dogstats.increment("authn_kv", tags: ["action:write", "callsite:authentication_limit"])
          GitHub::Authentication::KV.store.increment(rate_limit_key(key), expires: @ttl.from_now, touch_on_insert: true)
        end

        if limit == @max_tries && @ban_ttl
          ActiveRecord::Base.connected_to(role: :writing) do
            GitHub.dogstats.increment("authn_kv", tags: ["action:write", "callsite:authentication_limit"])
            GitHub::Authentication::KV.store.set(rate_limit_key(key), limit.to_s, expires: @ban_ttl.from_now)
          end
        end

        limit
      rescue GitHub::KV::UnavailableError => error
        Failbot.report(error)
        return false
      end
    else
      GitHub.dogstats.increment("authn_kv", tags: ["action:read", "callsite:authentication_limit"])
      GitHub::Authentication::KV.store.get(rate_limit_key(key)).value do |error|
        Failbot.report(error)
        return false
      end
    end

    at_limit = tries.to_i >= @max_tries

    GitHub.dogstats.increment("account_security.at_rate_limit", tags: [
      "kv:#{at_limit}",
      "increment:#{increment}",
      "name:#{name}",
    ])

    at_limit
  end

  # The RateLimiter key to use in KV for a given value.
  #
  # value  - The value being checked against RateLimiter.
  #
  # Returns a string key.
  def rate_limit_key(value)
    "rate_limit:auth_limit_by_#{name}:#{Digest::SHA256.hexdigest(value.to_s)}"
  end

  def whitelisted?(value)
    AuthenticationLimitWhitelistEntry.whitelisted?(@whitelist_key.to_s, value).tap do |res|
      GitHub.dogstats.increment("auth", tags: ["action:whitelisted"]) if res
    end
  end

  def event_prefix
    :lockout
  end

  # Instrument account/ip lockout
  #
  # Returns nothing.
  def instrument_lockout(from:, actor_ip:, **data)
    GitHub.dogstats.increment "lockout", tags: ["name:#{name}", "from:#{from}"]

    user = self.class.user(data)

    payload = {
      user: user,
      actor: user,
      actor_ip: actor_ip || data[:ip] || data[:web_ip],
      from: from,
    }

    instrument name, payload
  end

  def instrument_remove(user)
    payload = {
      limit_name: name,
      user: user,
    }

    instrument :remove, payload
  end
end

# Load configuration
load File.join(ENV["RAILS_ROOT"], "config", "authentication_limits.rb")
