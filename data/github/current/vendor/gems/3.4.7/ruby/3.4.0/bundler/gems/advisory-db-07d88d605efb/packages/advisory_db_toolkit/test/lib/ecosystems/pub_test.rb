# frozen_string_literal: true

require "test_helper"

module AdvisoryDBToolkit
  class EcosystemsPubTest < Minitest::Test
    def setup
      WebMock.reset!
      AdvisoryDBToolkit::PackageUrlObtainer.http_client = Tools::HttpClient.new
    end
    
    def test_get_package_returns_package_info_for_queried_package
      package_name = "http"
      VCR.use_cassette("ecosystems_pub_package_http") do
        package = AdvisoryDBToolkit::Ecosystems::Pub.get_package(package_name)
        assert_equal package_name, package["name"]
        assert_equal 3, package.count
      end

      WebMock.assert_requested(:get, "https://pub.dev/api/packages/#{package_name}", times: 1)
    end

    def test_get_package_returns_nil_when_package_does_not_exist
      package_name = "package_not_found"
      VCR.use_cassette("ecosystems_pub_package_notfound") do
        assert_nil AdvisoryDBToolkit::Ecosystems::Pub.get_package(package_name)
      end

      WebMock.assert_requested(:get, "https://pub.dev/api/packages/#{package_name}", times: 1)
    end

    def test_get_package_raises_an_error_when_invalid_status_is_returned
      package_name = "("
      assert_raises(AdvisoryDBToolkit::Ecosystems::Exceptions::ApiError) do
        VCR.use_cassette("ecosystems_pub_package_error") do
          AdvisoryDBToolkit::Ecosystems::Pub.get_package(package_name)
        end
      end

      WebMock.assert_requested(:get, "https://pub.dev/api/packages/#{package_name}", times: 1)
    end

    def test_get_package_url_returns_package_url_for_queried_package
      package_name = "http"
      VCR.use_cassette("ecosystems_pub_package_http") do
        url = AdvisoryDBToolkit::Ecosystems::Pub.get_package_url(package_name)
        assert_equal "https://pub.dev/packages/http", url
      end

      WebMock.assert_requested(:get, "https://pub.dev/api/packages/#{package_name}", times: 1)
    end

    def test_get_package_url_returns_nil_when_package_does_not_exit
      package_name = "package_not_found"
      VCR.use_cassette("ecosystems_pub_package_notfound") do
        assert_nil AdvisoryDBToolkit::Ecosystems::Pub.get_package_url(package_name)
      end

      WebMock.assert_requested(:get, "https://pub.dev/api/packages/#{package_name}", times: 1)
    end
  end
end
