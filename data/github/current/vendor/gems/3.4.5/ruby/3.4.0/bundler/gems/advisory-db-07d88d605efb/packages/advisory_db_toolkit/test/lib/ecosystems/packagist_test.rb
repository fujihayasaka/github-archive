# frozen_string_literal: true

require "test_helper"

module AdvisoryDBToolkit
  class EcosystemsPackagistTest < Minitest::Test
    def setup
      WebMock.reset!
      AdvisoryDBToolkit::PackageUrlObtainer.http_client = Tools::HttpClient.new
    end

    def test_get_package_metadata_returns_package_info_for_queried_package
      package_name = "monolog/monolog"
      VCR.use_cassette("ecosystems_packagist_metadata_monolog") do
        metadata = AdvisoryDBToolkit::Ecosystems::Packagist.get_package_metadata(package_name)
        package = metadata.dig("packages", package_name, 0)
        assert_equal package_name, package["name"]
        assert_equal "https://github.com/Seldaek/monolog", package["homepage"]
      end

      WebMock.assert_requested(:get, "https://repo.packagist.org/p2/#{package_name}.json", times: 1)
    end

    def test_get_package_metadata_returns_nil_when_package_does_not_exist
      package_name = "shouldnot/befound"
      VCR.use_cassette("ecosystems_packagist_metadata_notfound") do
        assert_nil AdvisoryDBToolkit::Ecosystems::Packagist.get_package_metadata(package_name)
      end

      WebMock.assert_requested(:get, "https://repo.packagist.org/p2/#{package_name}.json", times: 1)
    end

    def test_get_package_metadata_raises_an_error_when_invalid_status_is_returned
      package_name = "shouldraise/anerror"
      assert_raises(AdvisoryDBToolkit::Ecosystems::Exceptions::ApiError) do
        VCR.use_cassette("ecosystems_packagist_metadata_error") do
          AdvisoryDBToolkit::Ecosystems::Packagist.get_package_metadata(package_name)
        end
      end

      WebMock.assert_requested(:get, "https://repo.packagist.org/p2/#{package_name}.json", times: 1)
    end

    def test_get_package_url_returns_package_url_for_queried_package
      package_name = "monolog/monolog"
      VCR.use_cassette("ecosystems_packagist_metadata_monolog") do
        url = AdvisoryDBToolkit::Ecosystems::Packagist.get_package_url(package_name)
        assert_equal "https://packagist.org/packages/monolog/monolog", url
      end

      WebMock.assert_requested(:get, "https://repo.packagist.org/p2/#{package_name}.json", times: 1)
    end

    def test_get_package_url_returns_nil_when_package_does_not_exit
      package_name = "shouldnot/befound"
      VCR.use_cassette("ecosystems_packagist_metadata_notfound") do
        assert_nil AdvisoryDBToolkit::Ecosystems::Packagist.get_package_url(package_name)
      end

      WebMock.assert_requested(:get, "https://repo.packagist.org/p2/#{package_name}.json", times: 1)
    end
  end
end
