# frozen_string_literal: true

require "test_helper"

module AdvisoryDBToolkit
  class EcosystemsNugetTest < Minitest::Test
    def setup
      WebMock.reset!
      AdvisoryDBToolkit::PackageUrlObtainer.http_client = Tools::HttpClient.new
    end

    def test_api_returns_api_response_for_the_queried_route
      VCR.use_cassette("ecosystems_nuget_api_service_index") do
        response = AdvisoryDBToolkit::Ecosystems::Nuget.api("index.json")
        assert_equal 200, response.status
        data = JSON.parse response.body
        assert_equal 37, data["resources"].count
      end
      WebMock.assert_requested(:get, "https://api.nuget.org/v3/index.json", times: 1)
    end

    def test_get_package_metadata_returns_package_info_for_queried_package
      package_name = "NuGet.Server.Core"
      VCR.use_cassette("ecosystems_nuget_metadata_core") do
        metadata = AdvisoryDBToolkit::Ecosystems::Nuget.get_package_metadata(package_name)
        assert_equal package_name, metadata.dig("items", 0, "items", 0, "catalogEntry", "id")
      end

      WebMock.assert_requested(:get, "https://api.nuget.org/v3/registration5-semver1/#{package_name.downcase}/index.json", times: 1)
    end

    def test_get_package_metadata_returns_nil_when_package_does_not_exist
      package_name = "NuGet.Invalid.Package"
      VCR.use_cassette("ecosystems_nuget_metadata_notfound") do
        assert_nil AdvisoryDBToolkit::Ecosystems::Nuget.get_package_metadata(package_name)
      end

      WebMock.assert_requested(:get, "https://api.nuget.org/v3/registration5-semver1/#{package_name.downcase}/index.json", times: 1)
    end

    def test_get_package_metadata_raises_an_error_when_invalid_status_is_returned
      package_name = "NuGet.Throws.Error"
      assert_raises(AdvisoryDBToolkit::Ecosystems::Exceptions::ApiError) do
        VCR.use_cassette("ecosystems_nuget_metadata_error") do
          AdvisoryDBToolkit::Ecosystems::Nuget.get_package_metadata(package_name)
        end
      end

      WebMock.assert_requested(:get, "https://api.nuget.org/v3/registration5-semver1/#{package_name.downcase}/index.json", times: 1)
    end

    def test_get_package_url_returns_package_url_for_queried_package
      package_name = "NuGet.Server.Core"
      VCR.use_cassette("ecosystems_nuget_metadata_core") do
        url = AdvisoryDBToolkit::Ecosystems::Nuget.get_package_url(package_name)
        assert_equal "https://www.nuget.org/packages/NuGet.Server.Core", url
      end

      WebMock.assert_requested(:get, "https://api.nuget.org/v3/registration5-semver1/#{package_name.downcase}/index.json", times: 1)
    end

    def test_get_package_url_returns_nil_when_package_does_not_exit
      package_name = "NuGet.Invalid.Package"
      VCR.use_cassette("ecosystems_nuget_metadata_notfound") do
        assert_nil AdvisoryDBToolkit::Ecosystems::Nuget.get_package_url(package_name)
      end

      WebMock.assert_requested(:get, "https://api.nuget.org/v3/registration5-semver1/#{package_name.downcase}/index.json", times: 1)
    end
  end
end
