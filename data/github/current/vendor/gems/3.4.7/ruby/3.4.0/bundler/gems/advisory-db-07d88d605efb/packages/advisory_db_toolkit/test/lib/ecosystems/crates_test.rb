# frozen_string_literal: true

require "test_helper"

module AdvisoryDBToolkit
  class EcosystemsCratesTest < Minitest::Test
    def setup
      WebMock.reset!
      AdvisoryDBToolkit::PackageUrlObtainer.http_client = Tools::HttpClient.new
    end
  
    def test_get_crate_returns_crate_for_queried_package
      package_name = "rand"
      VCR.use_cassette("ecosystems_crates_package_rand") do
        crate = AdvisoryDBToolkit::Ecosystems::Crates.get_crate(package_name)
        assert_equal package_name, crate.dig("crate", "id")
      end

      WebMock.assert_requested(:get, "https://crates.io/api/v1/crates/#{package_name}", times: 1)
    end

    def test_get_crate_returns_nil_when_package_does_not_exist
      package_name = "notfound"
      VCR.use_cassette("ecosystems_crates_package_notfound") do
        assert_nil AdvisoryDBToolkit::Ecosystems::Crates.get_crate(package_name)
      end

      WebMock.assert_requested(:get, "https://crates.io/api/v1/crates/#{package_name}", times: 1)
    end

    def test_get_crate_raises_an_error_when_invalid_status_is_returned
      package_name = "shoulderror"
      assert_raises(AdvisoryDBToolkit::Ecosystems::Exceptions::ApiError) do
        VCR.use_cassette("ecosystems_crates_package_error") do
          AdvisoryDBToolkit::Ecosystems::Crates.get_crate(package_name)
        end
      end

      WebMock.assert_requested(:get, "https://crates.io/api/v1/crates/#{package_name}", times: 1)
    end

    def test_get_package_url_returns_package_url_for_queried_package
      package_name = "rand"
      VCR.use_cassette("ecosystems_crates_package_rand") do
        url = AdvisoryDBToolkit::Ecosystems::Crates.get_package_url(package_name)
        assert_equal "https://crates.io/crates/rand", url
      end

      WebMock.assert_requested(:get, "https://crates.io/api/v1/crates/#{package_name}", times: 1)
    end

    def test_get_package_url_returns_nil_when_package_does_not_exist
      package_name = "notfound"
      VCR.use_cassette("ecosystems_crates_package_notfound") do
        assert_nil AdvisoryDBToolkit::Ecosystems::Crates.get_package_url(package_name)
      end

      WebMock.assert_requested(:get, "https://crates.io/api/v1/crates/#{package_name}", times: 1)
    end

    def test_get_package_url_returns_nil_when_API_errors
      package_name = "bottlerocket/update-operator"
      VCR.use_cassette("ecosystems_crates_bottlerocket_api_error") do
        assert_nil AdvisoryDBToolkit::Ecosystems::Crates.get_package_url(package_name)
      end

      WebMock.assert_requested(:get, "https://crates.io/api/v1/crates/#{package_name}", times: 1)
    end
  end
end
