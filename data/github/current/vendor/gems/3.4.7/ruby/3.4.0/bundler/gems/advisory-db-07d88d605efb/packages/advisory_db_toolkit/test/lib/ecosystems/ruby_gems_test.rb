# frozen_string_literal: true

require "test_helper"

module AdvisoryDBToolkit
  class EcosystemsRubyGemsTest < Minitest::Test
    def setup
      WebMock.reset!
      AdvisoryDBToolkit::PackageUrlObtainer.http_client = Tools::HttpClient.new
    end
    
    def test_api_returns_search_results_for_a_query
      params = { query: "cookie_parser" }
      VCR.use_cassette("ecosystems_ruby_gems_api_cookie_parser_gem") do
        res = AdvisoryDBToolkit::Ecosystems::RubyGems.api("search.json", params:)
        assert_equal 200, res.status
        data = JSON.parse res.body
        assert_equal 2, data.length
        assert_equal "https://rubygems.org/gems/ga_cookie_parser", data[0]["project_uri"]
      end

      WebMock.assert_requested(:get, "https://rubygems.org/api/v1/search.json?#{URI.encode_www_form(params)}", times: 1)
    end

    def test_get_gem_returns_gem_info_for_queried_gem
      gem_name = "rails"
      VCR.use_cassette("ecosystems_ruby_gems_api_rails_gem") do
        gem = AdvisoryDBToolkit::Ecosystems::RubyGems.get_gem(gem_name)
        assert_equal gem_name, gem["name"]
        assert_equal "David Heinemeier Hansson", gem["authors"]
      end

      WebMock.assert_requested(:get, "https://rubygems.org/api/v1/gems/#{gem_name}.json", times: 1)
    end

    def test_get_gem_returns_nil_when_package_does_not_exist
      gem_name = "shouldnotbefound"
      VCR.use_cassette("ecosystems_ruby_gems_api_shouldnotbefound_gem") do
        gem = AdvisoryDBToolkit::Ecosystems::RubyGems.get_gem(gem_name)
        assert_nil gem
      end

      WebMock.assert_requested(:get, "https://rubygems.org/api/v1/gems/#{gem_name}.json", times: 1)
    end

    def test_get_gem_raises_an_error_when_invalid_status_is_returned
      gem_name = "testerror"
      assert_raises(AdvisoryDBToolkit::Ecosystems::Exceptions::ApiError) do
        VCR.use_cassette("ecosystems_ruby_gems_api_error") do
          gem = AdvisoryDBToolkit::Ecosystems::RubyGems.get_gem(gem_name)
          assert_nil gem
        end
      end

      WebMock.assert_requested(:get, "https://rubygems.org/api/v1/gems/#{gem_name}.json", times: 1)
    end

    def test_get_package_url_returns_package_url_for_queried_gem
      gem_name = "rails"
      VCR.use_cassette("ecosystems_ruby_gems_api_rails_gem") do
        package_url = AdvisoryDBToolkit::Ecosystems::RubyGems.get_package_url(gem_name)
        assert_equal "https://rubygems.org/gems/rails", package_url
      end

      WebMock.assert_requested(:get, "https://rubygems.org/api/v1/gems/#{gem_name}.json", times: 1)
    end

    def test_get_package_url_returns_nil_when_package_does_not_exist
      gem_name = "shouldnotbefound"
      VCR.use_cassette("ecosystems_ruby_gems_api_shouldnotbefound_gem") do
        package_url = AdvisoryDBToolkit::Ecosystems::RubyGems.get_package_url(gem_name)
        assert_nil package_url
      end

      WebMock.assert_requested(:get, "https://rubygems.org/api/v1/gems/#{gem_name}.json", times: 1)
    end
  end
end
