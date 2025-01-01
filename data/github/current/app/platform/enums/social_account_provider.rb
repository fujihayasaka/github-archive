# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class SocialAccountProvider < Platform::Enums::Base
      description "Software or company that hosts social media accounts."

      # Due to an unfortunate interaction between Rails autoloading and circular references, we need to autoload
      # the SocialAccount base class manually here before referencing its subclasses in the enum values below.
      # Otherwise, anything that requires this file before SocialAccount is loaded will fail with an
      # "uninitialized constant" error.
      SocialAccount

      value "GENERIC", "Catch-all for social media providers that do not yet have specific handling.",
        value: SocialAccounts::Generic.key

      value "FACEBOOK", "Social media and networking website.",
        value: SocialAccounts::Facebook.key
      value "HOMETOWN", "Fork of Mastodon with a greater focus on local posting.",
        value: SocialAccounts::Hometown.key
      value "INSTAGRAM", "Social media website with a focus on photo and video sharing.",
        value: SocialAccounts::Instagram.key
      value "LINKEDIN", "Professional networking website.",
        value: SocialAccounts::LinkedIn.key
      value "MASTODON", "Open-source federated microblogging service.",
        value: SocialAccounts::Mastodon.key
      value "REDDIT", "Social news aggregation and discussion website.",
        value: SocialAccounts::Reddit.key
      value "TWITCH", "Live-streaming service.",
        value: SocialAccounts::Twitch.key
      value "TWITTER", "Microblogging website.",
        value: SocialAccounts::Twitter.key
      value "YOUTUBE", "Online video platform.",
        value: SocialAccounts::YouTube.key
      value "NPM", "JavaScript package registry.",
        value: SocialAccounts::Npm.key
    end
  end
end
