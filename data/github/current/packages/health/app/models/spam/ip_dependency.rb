# typed: false
# frozen_string_literal: true

require "resolv" unless defined?(Resolv)

module Spam::IpDependency
  include ActionView::Helpers::DateHelper

  # Add each address passed to us to the (transient) Denylist.
  #
  # addresses - String or Array of Strings of IP addresses
  #
  # Returns nothing.
  def ip_denylist(addresses, params = nil)
    params ||= {}
    addresses = Array(addresses).uniq.compact
    addresses.each do |ip|
      if ip_is_denylisted?(ip)
        puts "#{ip} already denylisted." if params[:verbose]
      else
        puts "Denylisting #{ip}" if params[:verbose]
        Spam::Kv.store.set("spam.denylisted_ip.#{ip}", "1", expires: 1.week.from_now)
      end
    end
  end

  # Remove the given ip address from the Denylist.
  #
  # ip - String of the IP address to remove
  #
  # Returns true if the ip address was Denylisted (and removed),
  # or false if not.
  def ip_undenylist(ip, params = nil)
    params ||= {}
    if ip_is_denylisted?(ip)
      puts "Un-Denylisting #{ip}" if params[:verbose]
      Spam::Kv.store.del("spam.denylisted_ip.#{ip}")
      true
    else
      puts "#{ip} not denylisted." if params[:verbose]
      false
    end
  end

  # Check whether an ip address is currently on the Denylist.
  #
  # ip - String of the IP address to check.
  #
  # Returns true if the ip address is in the denylist, or nil if not.
  def ip_is_denylisted?(ip)
    Spam::Kv.store.get("spam.denylisted_ip.#{ip}").value { false }
  end

  # Look in the audit log for the user's creation entry, and get the
  # IP address from whence it came.
  #
  # user - the User or String login to look up
  #
  # Returns the String ip address from which the User was created if
  # found, or nil.
  def find_creation_ip_address(user)
    results = find_audit_events_for_user("user.create", user)
    if results.first
      results.first["actor_ip"]
    else
      puts "Failed to find creation IP for #{user}"
      nil
    end
  end

  def find_logins_for_user(user)
    user.find_logins
  end

  def find_login_ip_addresses(user)
    user.find_login_ip_addresses
  end

  def find_audit_events_for_user(event, user)
    if user.is_a? String
      actual_user = User.find_by_login(user)
      user = actual_user if actual_user && actual_user.user? # no Organizations plz
    end

    query = {
      actor_id: user.id,
      allowlist: [event],
    }
    Audit::Driftwood::Query.new_user_query(query).execute.results
  end

  VALID_FLAGGED_INTERVAL_THRESHOLD = 0

  def flagged_interval_in_words(user)
    interval = flagged_interval(user)
    if interval > 0
      time_ago_in_words(Time.now - interval)
    else
      "never"
    end
  end

  # Return the Time object for the first specified event for the given User,
  # or nil if there was none.
  def last_event_time(user, event)
    events = user.find_audit_events(event)
    last_event = events.last
    if last_event
      event = AuditLogEntry.new_from_hash(last_event)
      event.created_at
    end
  end

  def flagged_interval(user)
    interval = 0

    if flagged_at = last_event_time(user, "staff.mark_as_spammy")
      unflagged_at = last_event_time(user, "staff.mark_not_spammy")

      # If it hasn't been unflagged since last being flagged, interval extends
      # to the current moment.
      if unflagged_at.nil? || unflagged_at < flagged_at
        unflagged_at = Time.now
      end

      interval = unflagged_at - flagged_at
    end

    interval
  end

  def is_tor_node?(address)
    Spam::GeoAsnLookup.is_tor_node?(address)
  end

  def reverse_ip(address)
    address.split(".").reverse.join(".")
  end

  def getaddress(host)
    Resolv::DefaultResolver.each_address(host.to_s) do |addr|
      return addr.to_s if addr.to_s =~ Resolv::IPv4::Regex
    end
    raise Resolv::ResolvError.new("no address for #{host}")
  end

  SPAMMY_SAFELIST_KEY = "spam-safelist-ip"

  def ip_safelist_key(ip)
    "#{SPAMMY_SAFELIST_KEY}-#{ip}"
  end

  SPAMMY_SAFELIST_DEFAULT_EXPIRATION = 24.hours

  def ip_add_to_safelist(ip, expires_at: SPAMMY_SAFELIST_DEFAULT_EXPIRATION.from_now)
    return if ip.nil?

    Spam::Kv.store.set(ip_safelist_key(ip), "true", expires: expires_at)
  end

  def ip_remove_from_safelist(ip)
    return if ip.nil?

    Spam::Kv.store.del(ip_safelist_key(ip))
  end

  def ip_safelisted?(ip)
    return false if ip.nil?

    Spam::Kv.store.exists(ip_safelist_key(ip)).value { false }
  end
end
