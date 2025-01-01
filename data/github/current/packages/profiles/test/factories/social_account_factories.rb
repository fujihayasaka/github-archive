# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :social_account do
    transient do
      key { "generic" }
      meta { {} }
    end

    url { "https://example.com" }

    initialize_with { SocialAccount.create(key:, url:, meta:) }
    skip_create

    factory :social_account_facebook do
      key { "facebook" }
      url { "https://facebook.com/monalisa" }
    end

    factory :social_account_hometown do
      key { "hometown" }
      url { "https://digipres.club/@monalisa" }
    end

    factory :social_account_instagram do
      key { "instagram" }
      url { "https://instagram.com/monalisa" }
    end

    factory :social_account_linkedin do
      key { "linkedin" }
      url { "https://linkedin.com/in/monalisa" }
    end

    factory :social_account_mastodon do
      key { "mastodon" }
      url { "https://mastodon.social/@monalisa" }
    end

    factory :social_account_reddit do
      key { "reddit" }
      url { "https://reddit.com/u/monalisa" }
    end

    factory :social_account_twitch do
      key { "twitch" }
      url { "https://twitch.tv/monalisa" }
    end

    factory :social_account_twitter do
      key { "twitter" }
      url { "https://twitter.com/monalisa" }
    end

    factory :social_account_youtube do
      key { "youtube" }
      url { "https://youtube.com/@monalisa" }
    end

    factory :social_account_npm do
      key { "npm" }
      url { "https://npmjs.com/~monalisa" }
    end
  end
end
