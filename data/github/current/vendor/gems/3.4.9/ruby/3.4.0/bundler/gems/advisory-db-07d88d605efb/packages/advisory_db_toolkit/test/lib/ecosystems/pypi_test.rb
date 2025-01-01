# frozen_string_literal: true

require "test_helper"

module AdvisoryDBToolkit
  class EcosystemsPypiTest < Minitest::Test
    def setup
      WebMock.reset!
      AdvisoryDBToolkit::PackageUrlObtainer.http_client = Tools::HttpClient.new
    end

    def test_get_project_returns_project_info_for_queried_project
      project_name = "sampleproject"
      VCR.use_cassette("ecosystems_pypi_project_sampleproject") do
        project = AdvisoryDBToolkit::Ecosystems::Pypi.get_project(project_name)
        assert_equal project_name, project["info"]["name"]
        assert_equal "A. Random Developer", project["info"]["author"]
      end

      WebMock.assert_requested(:get, "https://pypi.org/pypi/#{project_name}/json", times: 1)
    end

    def test_get_project_returns_nil_when_package_does_not_exist
      project_name = "projectdoesntexist"
      VCR.use_cassette("ecosystems_pypi_project_projectdoesntexist") do
        project = AdvisoryDBToolkit::Ecosystems::Pypi.get_project(project_name)
        assert_nil project
      end

      WebMock.assert_requested(:get, "https://pypi.org/pypi/#{project_name}/json", times: 1)
    end

    def test_get_project_raises_an_error_when_invalid_status_is_returned
      project_name = "testerror"
      assert_raises(AdvisoryDBToolkit::Ecosystems::Exceptions::ApiError) do
        VCR.use_cassette("ecosystems_pypi_project_error") do
          AdvisoryDBToolkit::Ecosystems::Pypi.get_project(project_name)
        end
      end

      WebMock.assert_requested(:get, "https://pypi.org/pypi/#{project_name}/json", times: 1)
    end

    def test_get_package_url_returns_package_url_for_queried_package
      project_name = "sampleproject"
      VCR.use_cassette("ecosystems_pypi_project_sampleproject") do
        package_url = AdvisoryDBToolkit::Ecosystems::Pypi.get_package_url(project_name)
        assert_equal "https://pypi.org/project/sampleproject/", package_url
      end

      WebMock.assert_requested(:get, "https://pypi.org/pypi/#{project_name}/json", times: 1)
    end

    def test_get_package_url_returns_nil_when_package_does_not_exist
      project_name = "projectdoesntexist"
      VCR.use_cassette("ecosystems_pypi_project_projectdoesntexist") do
        package_url = AdvisoryDBToolkit::Ecosystems::Pypi.get_package_url(project_name)
        assert_nil package_url
      end

      WebMock.assert_requested(:get, "https://pypi.org/pypi/#{project_name}/json", times: 1)
    end
  end
end
