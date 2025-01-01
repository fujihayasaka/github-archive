# typed: true
# frozen_string_literal: true

require "github"
require "github/email/token"

module GitHub
  module Email
    # Creates an email address replying to the given target.
    #
    # target - ActiveRecord::Base instance.  It should have an associated
    #          mapping in TARGET_MAP.
    # user   - User instance that is replying.
    #
    # Returns a String email address.
    def self.reply_email(target, user)
      return GitHub.noreply_address unless GitHub.email_replies_enabled?

      if email = build_email(target, user)
        "reply+#{email}"
      end
    end

    # Creates an email address unsubscribing from the given target.
    #
    # target - ActiveRecord::Base instance.  It should have an associated
    #          mapping in TARGET_MAP.
    # user   - User instance that is replying.
    #
    # Returns a String email address.
    def self.unsub_email(target, user)
      if email = build_email(target, user)
        "unsub+#{email}"
      end
    end

    # Creates an email address for the given target.
    #
    # target - ActiveRecord::Base instance.  It should have an associated
    #          mapping in TARGET_MAP.
    # user   - User instance that is replying.
    #
    # Returns a String email address.
    def self.build_email(target, user)
      if token = GitHub::Email::Token.target_token(target, user)
        "#{token}@#{GitHub.urls.mail_reply_host_name}"
      end
    end
  end
end
