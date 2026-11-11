# typed: false
# frozen_string_literal: true

require "github/entitlements_ldap"

# Public: The entrypoint for knowing if a GitHub employee has permission to
# perform a Spamurai Next action; backed by spamurai-next-access LDAP entries
# in github/entitlements.
module SpamuraiNextAccess
  APP_DN = "ou=spamurai-next-access,ou=Apps,ou=Entitlements,ou=Groups,dc=github,dc=net"
  LDAP_ERRORS = [
    GitHub::EntitlementsLdap::LDAPConnectionError,
    GitHub::EntitlementsLdap::LDAPWTFError,
    Net::LDAP::Error,
  ]

  # Public: Does a user has a permission?
  # We first ask Spam::Kv.store if the user has a cached result.
  # If not we ask entitlements and cache the results.
  #
  # login - A GitHub login.
  # permission - The cn of a spamurai-next-access entitlement, ex: actions-classify-spammy.
  #
  # Returns a boolean.
  def self.user_has_permission?(login:, permission:)
    return true if login == "hubot"
    return true if cached_users_with_permission(permission).include?(login&.downcase)

    users = users_with_permission(permission)
    cache_users_with_permission(permission, users)

    users.include?(login&.downcase)
  rescue *LDAP_ERRORS
    # If we can't connect to LDAP, default to having access unless we're in production
    !Rails.env.production?
  end

  # Public: The users that have a spamurai-next-access.
  #
  # Returns a list of GitHub logins.
  def self.users_with_permission(permission)
    search = "cn=#{permission},#{APP_DN}"
    attrs = %w[uniquemember]
    client = GitHub.platform_health_entitlements_ldap_client

    users = []
    client.search(base: search, attrs: attrs, scope: Net::LDAP::SearchScope_BaseObject) do |entry|
      users += entry["uniquemember"].map do |member|
        # member has the format "uid=login,ou=People,dc=github,dc=net"
        member.split(",").find { |i| i.start_with?("uid=") }.sub("uid=", "")
      end
    end

    users
  end

  # Public: caches which user logins have a permission.
  # Cache expires after an hour.
  def self.cache_users_with_permission(permission, users)
    Spam::Kv.store.set(permission_cache_key(permission), users.to_json, expires: 1.hour.from_now)
  end

  # Public: retrive the cached set of user logins for a permission.
  #
  # Returns an array of GitHub login strings.
  def self.cached_users_with_permission(permission)
    value = Spam::Kv.store.get(permission_cache_key(permission)).value { "[]" }
    value ? JSON.parse(value) : []
  end

  # Public: the cache key for a permission.
  #
  # Returns a string.
  def self.permission_cache_key(permission)
    "spamurai_next_access:#{permission}"
  end
end
