# typed: false
# frozen_string_literal: true

module Spam::QueueDependency
  TAINTED_LOGIN_KEY_PREFIX = "spammy-tainted-logins"
  TAINTED_LOGIN_TTL        = 86400

  def spammy_tainted_login_queue
    @slrq ||= Spam::ExpiringQueue.new(TAINTED_LOGIN_KEY_PREFIX,
                                      TAINTED_LOGIN_TTL)
  end

  # Clear an existing tainted login
  #
  # login - String to un-taint
  #
  # Returns nothing.
  def clear_tainted_login(login)
    spammy_tainted_login_queue.clear login
  end

  # Set an auto-expiring value in the key/val store for this login.
  #
  # login - String to flag as tainted
  # value - Value to store; typically the `id` of the last User with this login
  #
  # Returns nothing.
  def mark_login_tainted(login, value = 1)
    spammy_tainted_login_queue.set login, value
  end

  # Check whether a given login is still on the "tainted" queue.
  #
  # login - String to check
  #
  # Returns the stored value if the key exists, and nil otherwise.
  def login_is_tainted?(login)
    spammy_tainted_login_queue.get login
  end

end
