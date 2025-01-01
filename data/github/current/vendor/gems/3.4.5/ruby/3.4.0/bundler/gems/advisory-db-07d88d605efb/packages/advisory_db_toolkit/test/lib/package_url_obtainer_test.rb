require "test_helper"
require "support/tools/http_client"

module AdvisoryDBToolkit
  class PackageUrlObtainerTest < Minitest::Test
    def setup
      @subject = AdvisoryDBToolkit::PackageUrlObtainer
    end

    def test_supported_ecosystem?
      assert_equal true, @subject.supported_ecosystem?("actions")
      assert_equal false, @subject.supported_ecosystem?("unsupported")
    end

    def test_get_url
      AdvisoryDBToolkit::Ecosystems::Actions.stubs(:get_package_url).returns("https://example.com")
      assert_equal "https://example.com", @subject.get_url("actions", 'package_name', Tools::HttpClient.new)
    end

    def test_get_url_returns_nil_for_unsupported_ecosystem
      assert_nil @subject.get_url("unsupported", 'package_name', Tools::HttpClient.new)
    end
  end
end
