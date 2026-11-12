# frozen_string_literal: true

require "test_helper"

module AdvisoryDBToolkit
  class EcosystemsMavenTest < Minitest::Test
    def setup
      WebMock.reset!
      AdvisoryDBToolkit::PackageUrlObtainer.http_client = Tools::HttpClient.new
    end

    def test_api_returns_search_results_for_a_query
      params = {
        q: "g:com.google.inject AND a:guice",
        core: "gav",
        rows: 5,
      }
      VCR.use_cassette("ecosystems_maven_api_guice_gav") do
        res = AdvisoryDBToolkit::Ecosystems::Maven.api(params)
        assert_equal 200, res.status
        data = JSON.parse res.body
        params.each_key { |key| assert_equal params[key].to_s, data.dig("responseHeader", "params", key.to_s) }
        assert_equal 5, data.dig("response", "docs").count
      end

      WebMock.assert_requested(:get, "https://search.maven.org/solrsearch/select?#{URI.encode_www_form(params)}", times: 1)
    end

    def test_artifact_by_group_id_returns_artifact_info_for_queried_artifact
      group_id = "com.google.inject"
      artifact_name = "guice"
      VCR.use_cassette("ecosystems_maven_get_artifact_guice") do
        artifact = AdvisoryDBToolkit::Ecosystems::Maven.get_artifact_by_group_id(artifact_name, group_id)
        assert_equal artifact_name, artifact["a"]
        assert_equal group_id, artifact["g"]
        assert_equal "central", artifact["repositoryId"]
      end

      WebMock.assert_requested(:get, "https://search.maven.org/solrsearch/select?q=a:#{artifact_name}%20AND%20g:#{group_id}", times: 1)
    end

    def test_get_artifact_by_group_id_returns_nil_when_artifact_does_not_exist
      group_id = "com.google.inject"
      artifact_name = "shouldnotbefound"
      VCR.use_cassette("ecosystems_maven_get_artifact_shouldnotbefound") do
        artifact = AdvisoryDBToolkit::Ecosystems::Maven.get_artifact_by_group_id(artifact_name, group_id)
        assert_nil artifact
      end

      WebMock.assert_requested(:get, "https://search.maven.org/solrsearch/select?q=a:#{artifact_name}%20AND%20g:#{group_id}", times: 1)
    end

    def test_get_artifact_by_group_id_raises_an_error_when_invalid_status_is_returned
      group_id = "\\"
      artifact_name = "shoulderror"
      assert_raises(AdvisoryDBToolkit::Ecosystems::Exceptions::ApiError) do
        VCR.use_cassette("ecosystems_maven_get_artifact_shoulderror") do
          AdvisoryDBToolkit::Ecosystems::Maven.get_artifact_by_group_id(artifact_name, group_id)
        end
      end

      WebMock.assert_requested(:get, "https://search.maven.org/solrsearch/select?q=a:#{artifact_name}%20AND%20g:#{group_id}", times: 1)
    end

    def test_get_package_url_returns_package_url_for_queried_package
      group_id = "com.google.inject"
      artifact_name = "guice"
      VCR.use_cassette("ecosystems_maven_get_artifact_guice") do
        package_url = AdvisoryDBToolkit::Ecosystems::Maven.get_package_url("#{group_id}:#{artifact_name}")
        assert_equal "https://central.sonatype.com/artifact/com.google.inject/guice/7.0.0", package_url
      end

      WebMock.assert_requested(:get, "https://search.maven.org/solrsearch/select?q=a:#{artifact_name}%20AND%20g:#{group_id}", times: 1)
    end

    def test_get_package_url_returns_nil_when_package_does_not_exist
      group_id = "com.google.inject"
      artifact_name = "shouldnotbefound"
      VCR.use_cassette("ecosystems_maven_get_artifact_shouldnotbefound") do
        package_url = AdvisoryDBToolkit::Ecosystems::Maven.get_package_url("#{group_id}:#{artifact_name}")
        assert_nil package_url
      end

      WebMock.assert_requested(:get, "https://search.maven.org/solrsearch/select?q=a:#{artifact_name}%20AND%20g:#{group_id}", times: 1)
    end
  end
end
