# frozen_string_literal: true

require "test_helper"

module AdvisoryDBToolkit
  class EcosystemsGoTest < Minitest::Test
    def setup
      WebMock.reset!
      AdvisoryDBToolkit::PackageUrlObtainer.http_client = Tools::HttpClient.new
    end

    def test_get_package_page_returns_the_page_for_the_queried_package
      package_name = "golang.org/x/tools"
      VCR.use_cassette("ecosystems_go_package_page_tools") do
        page = AdvisoryDBToolkit::Ecosystems::Go.get_package_page(package_name)
        assert_equal 200, page.status
        assert_equal "https://pkg.go.dev/golang.org/x/tools", page.env.url.to_s
      end

      WebMock.assert_requested(:get, "https://pkg.go.dev/#{package_name} ", times: 1)
    end

    def test_get_package_page_returns_nil_when_that_package_is_not_found
      package_name = "should/not/be/found"
      VCR.use_cassette("ecosystems_go_package_page_notfound") do
        page = AdvisoryDBToolkit::Ecosystems::Go.get_package_page(package_name)
        assert_nil page
      end

      WebMock.assert_requested(:get, "https://pkg.go.dev/#{package_name} ", times: 1)
    end

    def test_get_package_page_raises_an_error_when_invalid_status_is_returned
      package_name = "("
      assert_raises(AdvisoryDBToolkit::Ecosystems::Exceptions::ApiError) do
        VCR.use_cassette("ecosystems_go_package_page_error") do
          AdvisoryDBToolkit::Ecosystems::Go.get_package_page(package_name)
        end
      end

      WebMock.assert_requested(:get, "https://pkg.go.dev/#{package_name} ", times: 1)
    end

    def test_get_package_url_returns_package_url_for_queried_package
      package_name = "golang.org/x/tools"
      VCR.use_cassette("ecosystems_go_package_page_tools") do
        url = AdvisoryDBToolkit::Ecosystems::Go.get_package_url(package_name)
        assert_equal "https://pkg.go.dev/golang.org/x/tools", url
      end

      WebMock.assert_requested(:get, "https://pkg.go.dev/#{package_name} ", times: 1)
    end

    def test_get_package_url_returns_nil_when_package_does_not_exist
      package_name = "should/not/be/found"
      VCR.use_cassette("ecosystems_go_package_page_notfound") do
        url = AdvisoryDBToolkit::Ecosystems::Go.get_package_url(package_name)
        assert_nil url
      end

      WebMock.assert_requested(:get, "https://pkg.go.dev/#{package_name} ", times: 1)
    end
  end
end
