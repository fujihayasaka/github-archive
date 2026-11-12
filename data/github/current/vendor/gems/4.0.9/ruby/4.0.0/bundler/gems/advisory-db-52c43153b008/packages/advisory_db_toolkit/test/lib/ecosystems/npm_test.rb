# frozen_string_literal: true

require "test_helper"

module AdvisoryDBToolkit
  class EcosystemsNPMTest < Minitest::Test
    def setup
      WebMock.reset!
      AdvisoryDBToolkit::PackageUrlObtainer.http_client = Tools::HttpClient.new
    end
    
    def test_api_returns_package_info_for_queried_package
      package = "ssl"
      VCR.use_cassette("ecosystems_npm_api_ssl_package") do
        res = AdvisoryDBToolkit::Ecosystems::NPM.api(package)
        assert_equal 200, res.status
        data = JSON.parse res.body
        assert_equal package, data["name"]
      end

      WebMock.assert_requested(:get, "https://registry.npmjs.org/#{package}", times: 1)
    end

    def test_get_package_info_returns_package_info_for_queried_package
      package_name = "ssl"
      VCR.use_cassette("ecosystems_npm_api_ssl_package") do
        package = AdvisoryDBToolkit::Ecosystems::NPM.get_package_info(package_name)
        assert_equal package_name, package["name"]
        assert_equal "Verification of SSL certificates", package["description"]
        assert_equal 18, package.length
      end

      WebMock.assert_requested(:get, "https://registry.npmjs.org/#{package_name}", times: 1)
    end

    def test_get_package_info_returns_nil_when_package_does_not_exist
      package_name = "shouldnotbefoundinnpm"
      VCR.use_cassette("ecosystems_npm_api_notfound_package") do
        package = AdvisoryDBToolkit::Ecosystems::NPM.get_package_info(package_name)
        assert_nil package
      end

      WebMock.assert_requested(:get, "https://registry.npmjs.org/#{package_name}", times: 1)
    end

    def test_get_package_info_raises_an_error_when_invalid_status_is_returned
      package_name = "testerror"
      assert_raises(AdvisoryDBToolkit::Ecosystems::Exceptions::ApiError) do
        VCR.use_cassette("ecosystems_npm_api_error_package") do
          package = AdvisoryDBToolkit::Ecosystems::NPM.get_package_info(package_name)
          assert_nil package
        end
      end

      WebMock.assert_requested(:get, "https://registry.npmjs.org/#{package_name}", times: 1)
    end

    def test_get_package_url_returns_package_url_for_queried_package
      package_name = "ssl"
      VCR.use_cassette("ecosystems_npm_api_ssl_package") do
        package_url = AdvisoryDBToolkit::Ecosystems::NPM.get_package_url(package_name)
        assert_equal "https://www.npmjs.com/package/#{package_name}", package_url
      end

      WebMock.assert_requested(:get, "https://registry.npmjs.org/#{package_name}", times: 1)
    end

    def test_get_package_url_returns_nil_when_package_does_not_exit
      package_name = "shouldnotbefoundinnpm"
      VCR.use_cassette("ecosystems_npm_api_notfound_package") do
        package_url = AdvisoryDBToolkit::Ecosystems::NPM.get_package_url(package_name)
        assert_nil package_url
      end

      WebMock.assert_requested(:get, "https://registry.npmjs.org/#{package_name}", times: 1)
    end

    def test_get_package_url_raises_an_error_when_an_api_error_is_returned
      package_name = "testerror"
      assert_raises(AdvisoryDBToolkit::Ecosystems::Exceptions::ApiError) do
        VCR.use_cassette("ecosystems_npm_api_error_package") do
          package_url = AdvisoryDBToolkit::Ecosystems::NPM.get_package_url(package_name)
          assert_nil package_url
        end
      end

      WebMock.assert_requested(:get, "https://registry.npmjs.org/#{package_name}", times: 1)
    end
  end
end
