# frozen_string_literal: true

require "test_helper"

module AdvisoryDBToolkit
  class EcosystemsHexTest < Minitest::Test
    def setup
      WebMock.reset!
      AdvisoryDBToolkit::PackageUrlObtainer.http_client = Tools::HttpClient.new
    end

    def test_get_package_returns_package_info_for_queried_package
      package_name = "gettext"
      VCR.use_cassette("ecosystems_hex_package_gettext") do
        package = AdvisoryDBToolkit::Ecosystems::Hex.get_package(package_name)
        assert_equal package_name, package["name"]
        assert_equal "https://hexdocs.pm/gettext/", package["docs_html_url"]
      end

      WebMock.assert_requested(:get, "https://hex.pm/api/packages/#{package_name}", times: 1)
    end

    def test_get_package_returns_nil_when_package_does_not_exist
      package_name = "notfound"
      VCR.use_cassette("ecosystems_hex_package_notfound") do
        assert_nil AdvisoryDBToolkit::Ecosystems::Hex.get_package(package_name)
      end

      WebMock.assert_requested(:get, "https://hex.pm/api/packages/#{package_name}", times: 1)
    end

    def test_get_package_raises_an_error_when_invalid_status_is_returned
      package_name = "shoulderror"
      assert_raises(AdvisoryDBToolkit::Ecosystems::Exceptions::ApiError) do
        VCR.use_cassette("ecosystems_hex_package_error") do
          AdvisoryDBToolkit::Ecosystems::Hex.get_package(package_name)
        end
      end

      WebMock.assert_requested(:get, "https://hex.pm/api/packages/#{package_name}", times: 1)
    end

    def test_get_package_url_returns_package_url_for_queried_package
      package_name = "gettext"
      VCR.use_cassette("ecosystems_hex_package_gettext") do
        url = AdvisoryDBToolkit::Ecosystems::Hex.get_package_url(package_name)
        assert_equal "https://hex.pm/packages/gettext", url
      end

      WebMock.assert_requested(:get, "https://hex.pm/api/packages/#{package_name}", times: 1)
    end

    def test_get_package_url_returns_nil_when_package_does_not_exit
      package_name = "notfound"
      VCR.use_cassette("ecosystems_hex_package_notfound") do
        assert_nil AdvisoryDBToolkit::Ecosystems::Hex.get_package_url(package_name)
      end

      WebMock.assert_requested(:get, "https://hex.pm/api/packages/#{package_name}", times: 1)
    end
  end
end
