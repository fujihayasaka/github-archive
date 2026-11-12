# frozen_string_literal: true

require "test_helper"

module AdvisoryDBToolkit
  class EcosystemsActionsTest < Minitest::Test
    def setup
      WebMock.reset!
      AdvisoryDBToolkit::PackageUrlObtainer.http_client = Tools::HttpClient.new
    end

    def test_get_repo_returns_repo_info_for_queried_package
      package_name = "hashicorp/vault-action"
      VCR.use_cassette("ecosystems_actions_repo_hashicorp") do
        repo = AdvisoryDBToolkit::Ecosystems::Actions.get_repo(package_name)
        assert_equal package_name, repo["full_name"]
        assert_equal "https://github.com/hashicorp/vault-action", repo["html_url"]
      end

      WebMock.assert_requested(:get, "https://api.github.com/repos/#{package_name}", times: 1)
    end

    def test_get_repo_returns_nil_when_package_does_not_exist
      package_name = "shouldnot/befound"
      VCR.use_cassette("ecosystems_actions_repo_notfound") do
        assert_nil AdvisoryDBToolkit::Ecosystems::Actions.get_repo(package_name)
      end

      WebMock.assert_requested(:get, "https://api.github.com/repos/#{package_name}", times: 1)
    end

    def test_get_repo_raises_an_error_when_invalid_status_is_returned
      package_name = "shouldraise/anerror"
      assert_raises(AdvisoryDBToolkit::Ecosystems::Exceptions::ApiError) do
        VCR.use_cassette("ecosystems_actions_repo_error") do
          AdvisoryDBToolkit::Ecosystems::Actions.get_repo(package_name)
        end
      end

      WebMock.assert_requested(:get, "https://api.github.com/repos/#{package_name}", times: 1)
    end

    def test_get_package_url_returns_package_url_for_queried_package
      package_name = "hashicorp/vault-action"
      VCR.use_cassette("ecosystems_actions_repo_hashicorp") do
        url = AdvisoryDBToolkit::Ecosystems::Actions.get_package_url(package_name)
        assert_equal "https://github.com/hashicorp/vault-action", url
      end

      WebMock.assert_requested(:get, "https://api.github.com/repos/#{package_name}", times: 1)
    end

    def test_get_package_url_returns_nil_when_package_does_not_exist
      package_name = "shouldnot/befound"
      VCR.use_cassette("ecosystems_actions_repo_notfound") do
        assert_nil AdvisoryDBToolkit::Ecosystems::Actions.get_package_url(package_name)
      end

      WebMock.assert_requested(:get, "https://api.github.com/repos/#{package_name}", times: 1)
    end
  end
end
