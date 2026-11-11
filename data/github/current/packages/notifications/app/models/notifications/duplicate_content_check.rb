# typed: true
# frozen_string_literal: true

require "digest/sha1"

module Notifications
  class DuplicateContentCheck
    EXPIRES = 2.weeks
    FLAG = "1"

    # Initialize a new DuplicateContentCheck for a given user.
    #
    # user_id - an Integer user id, for tracking this user's content.
    #
    def initialize(user_id)
      @user_id = user_id
    end

    # Has this content been seen before?
    #
    # If KV is unavailable, returns false.
    #
    # content - the String content to check
    #
    # Returns true or false.
    def duplicate?(content)
      value = Notifications::KV.store.get(key_for(content)).value { nil }
      value == FLAG
    end

    # Mark the given content as having been seen.
    #
    # The flag marking this content expires in EXPIRES seconds.
    #
    # content - the String content we've seen
    #
    def save(content)
      Notifications::KV.store.set key_for(content), FLAG, expires: EXPIRES.from_now
    rescue GitHub::KV::UnavailableError
      # carry on.
    end

    protected

    def key_for(content)
      length = content.length
      sha = Digest::SHA256.hexdigest(content)[0...7]
      "duplicate-content:#{@user_id}:#{length}:#{sha}"
    end
  end
end
