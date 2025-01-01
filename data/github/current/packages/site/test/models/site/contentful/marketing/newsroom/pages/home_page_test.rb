# typed: true
# frozen_string_literal: true

require "test_helper"

class SiteContentfulNewsroomPagesNewsroomPageTest < GitHub::TestCase
  require_cassettes_for_external_http_connections

  setup do
    skip if GitHub.enterprise?

    enable_feature_flag(:contentful_response_validation)
    @home_page = Site::Contentful::Marketing::Newsroom::Pages::HomePage.new
  end

  def valid_page_stub
    Site::Contentful::Marketing::Newsroom::ContentTypes::ContainerPage.stubs(:get_raw_json_for).returns(JSON.parse(File.read(Rails.root.join("test/fixtures/site/contentful/newsroom/home-page-valid.json"))))
  end

  def invalid_page_stub
    # One heroStatistics item is missing (must contain 3)
    Site::Contentful::Marketing::Newsroom::ContentTypes::ContainerPage.stubs(:get_raw_json_for).returns(JSON.parse(File.read(Rails.root.join("test/fixtures/site/contentful/newsroom/home-page-invalid.json"))))
  end

  context "#fetch_data_from_contentful" do
    test "returns the results from Contentful" do
      VCR.use_cassette("contentful/newsroom/pages/home-page") do
        assert_instance_of(Hash, @home_page.view_data)
        assert_equal(@home_page.view_data[:contentful_raw_json_response]["items"].size, 1)
      end
    end

    test "returns something that can be converted into JSON inside the contentful_raw_json_response" do
      VCR.use_cassette("contentful/newsroom/pages/home-page") do
        assert_nothing_raised do
          JSON.parse(@home_page.view_data.to_json)
        end
      end
    end

    test "confirm that expected keys appear in view_data" do
      VCR.use_cassette("contentful/newsroom/pages/home-page") do
        keys = @home_page.view_data.keys
        expected_keys = [:contentful_raw_json_response, :feature_flag, :global_navbar_style, :seo, :title, :use_dark_mode]
        assert(expected_keys.all? { |key| keys.include?(key) })
      end
    end
  end

  context "page_data" do
    test "returns correct SEO data" do
      VCR.use_cassette("contentful/newsroom/pages/home-page") do
        assert_equal(@home_page.title, "Newsroom Test")
        assert_equal(@home_page.view_data[:seo][:description], "A place for information about Github")
        assert_equal(@home_page.view_data[:seo][:social_media_image], "https://images.ctfassets.net/8aevphvgewt8/6aEF0LnKI9Tjgv81ggzpCD/b1af8fd613a72ba9644ec3a1650d8b79/github-logo-productivity-theme.webp")
      end
    end
  end

  context "validate!" do
    test "passes to the cache with valid entry data" do
      valid_page_stub

      subject = Site::Contentful::Marketing::Newsroom::Pages::HomePage.new
      subject.expects(:save_page_data_in_cache).once
      subject.revalidate
    end

    test "stops the cache with invalid entry data" do
      invalid_page_stub

      subject = Site::Contentful::Marketing::Newsroom::Pages::HomePage.new
      subject.expects(:save_page_data_in_cache).never
      subject.revalidate
    end
  end
end
