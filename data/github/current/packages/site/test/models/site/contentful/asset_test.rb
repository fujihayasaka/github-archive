# typed: true
# frozen_string_literal: true

require "test_helper"

class Site::Contentful::AssetTest < GitHub::TestCase
  unless GitHub.enterprise?
    def setup
      @image_asset = VCR.use_cassette("contentful/readme-featured-article-react") do
        Site::Contentful::Readme::FeaturedArticle.find("react", include_unpublished: true)
          .hero_image
      end
    end

    test "#absolute_url adds 'https' to the url if needed" do
      assert_match /^https:/, @image_asset.absolute_url
    end

    test "#absolute_url doesn't add 'https' if the url already begins with 'http'" do
      @image_asset.stubs(:url).returns("http://example.com/image.jpg")

      refute_match /^https:/, @image_asset.absolute_url
    end
  end
end
