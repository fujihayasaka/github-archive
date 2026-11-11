# typed: strict
# frozen_string_literal: true

module Storage
  module FastlyListingScreenshotsDependency
    extend T::Helpers
    include FastlyDependency

    abstract!

    # Name of the CDN service being used by Fastly
    sig { override.returns(String) }
    def storage_fastly_acceleration_bucket
      "marketplace-screenshots.githubusercontent.com"
    end

    sig { override.returns(T.nilable(String)) }
    def fastly_dictionary_key_name
      "key1"
    end

    sig { override.returns(T.nilable(String)) }
    def fastly_dictionary_key_value
      GitHub.private_listing_screenshot_cdn_key
    end

    sig { override.returns(T.nilable(String)) }
    def fastly_jwt_audience
      GitHub.marketplace_screenshots_cdn_url
    end
  end
end
