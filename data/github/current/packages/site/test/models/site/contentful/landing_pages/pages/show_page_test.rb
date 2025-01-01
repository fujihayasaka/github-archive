# typed: true
# frozen_string_literal: true

require "test_helper"

class SiteContentfulLandingPagesPagesShowPageTest < GitHub::TestCase
  require_cassettes_for_external_http_connections

  setup do
    skip if GitHub.enterprise?

    @show_page = Site::Contentful::Marketing::LandingPages::Pages::ShowPage.new(slug: "/contentful-e2e-test-do-not-remove")
  end

  context "#fetch_data_from_contentful" do
    test "returns the right data from Contentful" do
      VCR.use_cassette("contentful/landing-pages/pages/show-page") do
        data = @show_page.fetch_data_from_contentful

        assert_equal("Contentful E2E test: Do not remove", data[:title])
        assert_instance_of(Hash, data[:contentful_raw_json_response])
      end
    end

    test "ignores .html filename if given" do
      VCR.use_cassette("contentful/landing-pages/pages/show-page.html") do
        subject = Site::Contentful::Marketing::LandingPages::Pages::ShowPage.new(slug: "/contentful-e2e-test-do-not-remove.html")
        data = subject.fetch_data_from_contentful

        assert_equal("Contentful E2E test: Do not remove", data[:title])
        assert_instance_of(Hash, data[:contentful_raw_json_response])
      end
    end

    test "returns something that can be converted into JSON inside the contentful_raw_json_response" do
      VCR.use_cassette("contentful/landing-pages/pages/show-page") do
        data = @show_page.fetch_data_from_contentful

        assert_nothing_raised do
          JSON.parse(data[:contentful_raw_json_response].to_json)
        end
      end
    end

    test "returns nil if the page does not exist" do
      VCR.use_cassette("contentful/landing-pages/pages/show-page-404") do
        subject = Site::Contentful::Marketing::LandingPages::Pages::ShowPage.new(slug: "/a-page-that-does-not-exist")

        data = subject.fetch_data_from_contentful

        assert_nil data
      end
    end

    test "returns the name of the feature flag for this page" do
      VCR.use_cassette("contentful/landing-pages/pages/show-page") do
        subject = Site::Contentful::Marketing::LandingPages::Pages::ShowPage.new(slug: "/contentful-e2e-test-do-not-remove")

        data = subject.fetch_data_from_contentful

        assert_equal "contentful_lp_e2e_test", data[:feature_flag]
      end
    end

    test "returns nil if the page does not have a feature flag" do
      VCR.use_cassette("contentful/landing-pages/pages/show-page-with-no-settings") do
        subject = Site::Contentful::Marketing::LandingPages::Pages::ShowPage.new(slug: "/contentful-e2e-no-settings-test-do-not-remove")

        data = subject.fetch_data_from_contentful

        assert_nil data[:feature_flag]
      end
    end

    test "gets template name" do
      VCR.use_cassette("contentful/landing-pages/pages/show-page") do
        subject = Site::Contentful::Marketing::LandingPages::Pages::ShowPage.new(slug: "/contentful-e2e-test-do-not-remove")

        data = subject.fetch_data_from_contentful

        assert_equal("templateFreeForm", data[:template_name])
      end
    end

    context "handling use_dark_mode" do
      test "sets use_dark_mode to true if the page uses dark mode" do
        VCR.use_cassette("contentful/landing-pages/pages/show-page") do
          subject = Site::Contentful::Marketing::LandingPages::Pages::ShowPage.new(slug: "/contentful-e2e-test-do-not-remove")

          data = subject.fetch_data_from_contentful

          assert data.fetch(:use_dark_mode)
        end
      end

      test "sets use_dark_mode to false if the page does not use dark mode" do
        VCR.use_cassette("contentful/landing-pages/pages/show-page-with-no-settings") do
          subject = Site::Contentful::Marketing::LandingPages::Pages::ShowPage.new(slug: "/contentful-e2e-no-settings-test-do-not-remove")

          data = subject.fetch_data_from_contentful

          assert_equal false, data.fetch(:use_dark_mode)
        end
      end
    end

    context "handling page SEO" do
      test "returns an empty object if the page does not have SEO" do
        VCR.use_cassette("contentful/landing-pages/pages/show-page-with-no-seo") do
          subject = Site::Contentful::Marketing::LandingPages::Pages::ShowPage.new(slug: "/contentful-lp-tests/no-seo")

          data = subject.fetch_data_from_contentful

          assert_equal({}, data[:seo])
        end
      end

      test "returns an object with SEO information if it does exist" do
        VCR.use_cassette("contentful/landing-pages/pages/show-page-with-seo") do
          subject = Site::Contentful::Marketing::LandingPages::Pages::ShowPage.new(slug: "/contentful-lp-tests/with-seo")

          data = subject.fetch_data_from_contentful

          assert_equal "foo", data[:seo][:description]
          assert_match %r{https://images\.ctfassets\.net/}, data[:seo][:social_media_image]
        end
      end
    end

    context "handling metadata" do
      test "returns correct revenue play" do
        VCR.use_cassette("contentful/landing-pages/pages/show-page") do
          data = @show_page.fetch_data_from_contentful

          assert_equal("Platform", data[:revenue_play])
        end
      end

      test "returns nil when the page settings does not have revenue play set" do
        VCR.use_cassette("contentful/landing-pages/pages/show-page-with-no-revenue-setting") do
          subject = Site::Contentful::Marketing::LandingPages::Pages::ShowPage.new(slug: "/contentful-lp-tests/example-of-f2")
          data = subject.fetch_data_from_contentful

          assert_nil data[:revenue_play]
        end
      end
    end

    context "handling global navbar style" do
      test "returns nil if the page does not have a global navbar style" do
        VCR.use_cassette("contentful/landing-pages/pages/show-page-with-no-navbar-style") do
          subject = Site::Contentful::Marketing::LandingPages::Pages::ShowPage.new(slug: "/contentful-lp-tests/with-no-navbar-style")

          data = subject.fetch_data_from_contentful

          assert_nil data[:global_navbar_style]
        end
      end

      test "returns nil if the page uses the default global navbar style" do
        VCR.use_cassette("contentful/landing-pages/pages/show-page-with-default-navbar-style") do
          subject = Site::Contentful::Marketing::LandingPages::Pages::ShowPage.new(slug: "/contentful-lp-tests/with-default-navbar-style")

          data = subject.fetch_data_from_contentful

          assert_nil data[:global_navbar_style]
        end
      end

      test "returns white if the page uses the white global navbar style" do
        VCR.use_cassette("contentful/landing-pages/pages/show-page-with-white-navbar-style") do
          subject = Site::Contentful::Marketing::LandingPages::Pages::ShowPage.new(slug: "/contentful-lp-tests/with-white-navbar-style")

          data = subject.fetch_data_from_contentful

          assert_equal "white", data[:global_navbar_style]
        end
      end
    end
  end

  context "#cache_key" do
    test "builds the right key" do
      assert_equal "site.swp.landing_pages./contentful-e2e-test-do-not-remove", @show_page.cache_key
    end
  end
end
