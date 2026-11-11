# frozen_string_literal: true

require "test_helper"

# TO RECORD NEW VCR CASSETTES FOR THE DEPENDENCY GRAPH CLIENT:
#
# 1. You must do this from your local machine, it will not work from a codespaces container
# 2. Get a temporary HMAC token using chat ops; see https://github.com/github/dependency-graph-api/blob/master/docs/hmac_personal_keys.md#temporary-hmac-token-with-graphiql for details
# 3. Set `DEPENDENCY_GRAPH_API_TEMP_HMAC_TOKEN` with your temporary token in `.test.env` (DO NOT CHECK THIS CHANGE IN!)
# 4. Connect to the VPN
# 5. Run your tests
# 6. Temporary tokens expire after ~10 minutes

class DependencyGraphClientTest < ActiveSupport::TestCase
  setup do
    @old_api_slow_query_url = ENV["DEPENDENCY_GRAPH_API_SLOW_QUERY_URL"].dup
    @old_api_temp_hmac_key = ENV["DEPENDENCY_GRAPH_API_HMAC_KEY"].dup
    @old_api_url = ENV["DEPENDENCY_GRAPH_API_URL"].dup

    # Do not overwrite this with a temp key. See instructions above.
    ENV["DEPENDENCY_GRAPH_API_HMAC_KEY"] ||= "dg.api.test.hmac.key"
    ENV["DEPENDENCY_GRAPH_API_SLOW_QUERY_URL"] = "https://dependency-graph-api-slow-queries.service.iad.github.net/query"
    ENV["DEPENDENCY_GRAPH_API_URL"] = "https://dependency-graph-api.service.iad.github.net/query"

    @client = DependencyGraph::Client.new
  end

  teardown do
    ENV["DEPENDENCY_GRAPH_API_SLOW_QUERY_URL"] = @old_api_slow_query_url
    ENV["DEPENDENCY_GRAPH_API_HMAC_KEY"] = @old_api_temp_hmac_key
    ENV["DEPENDENCY_GRAPH_API_URL"] = @old_api_url
  end

  test "sets default connection settings from ENV variables" do
    assert_equal "https://dependency-graph-api.service.iad.github.net/query", @client.api_url
    assert_equal "https://dependency-graph-api-slow-queries.service.iad.github.net/query", @client.slow_query_api_url
    assert_equal ENV.fetch("DEPENDENCY_GRAPH_API_HMAC_KEY", nil), @client.hmac_key
  end

  test "can override default connection settings" do
    client = DependencyGraph::Client.new(
      api_url: "http://dg-api.net",
      slow_query_api_url: "http://dg-api-slow.net",
      hmac_key: "key.override",
    )
    assert_equal "http://dg-api.net", client.api_url
    assert_equal "http://dg-api-slow.net", client.slow_query_api_url
    assert_equal "key.override", client.hmac_key
  end

  test "is enabled if all connection settings are present" do
    assert @client.enabled?
  end

  test "is disabled if any of the connection settings are not set" do
    api_slow_query_url = ENV["DEPENDENCY_GRAPH_API_SLOW_QUERY_URL"].dup
    api_temp_hmac_key = ENV["DEPENDENCY_GRAPH_API_HMAC_KEY"].dup
    api_url = ENV["DEPENDENCY_GRAPH_API_URL"].dup

    ENV["DEPENDENCY_GRAPH_API_SLOW_QUERY_URL"] = nil
    client_1 = DependencyGraph::Client.new
    refute client_1.enabled?
    ENV["DEPENDENCY_GRAPH_API_SLOW_QUERY_URL"] = api_slow_query_url

    ENV["DEPENDENCY_GRAPH_API_HMAC_KEY"] = nil
    client_2 = DependencyGraph::Client.new
    refute client_2.enabled?
    ENV["DEPENDENCY_GRAPH_API_HMAC_KEY"] = api_temp_hmac_key

    ENV["DEPENDENCY_GRAPH_API_URL"] = nil
    client_3 = DependencyGraph::Client.new
    refute client_3.enabled?
    ENV["DEPENDENCY_GRAPH_API_URL"] = api_url
  end

  test "get_package_repo returns name of package repo when known" do
    ecosystem = AdvisoryDB.dependency_graph_ecosystem("rubygems")

    VCR.use_cassette("dependency_graph_client_get_package_repo") do
      repo = @client.get_package_repo(package_manager: ecosystem,
        package_name: "rails")
      assert_equal "rails/rails", repo
    end

    WebMock.assert_requested(:post, "https://dependency-graph-api.service.iad.github.net/query", times: 1) do |req|
      refute_nil req.headers["X-Request-Hmac"]
      variables = JSON.parse(req.body)["variables"]
      assert_equal ecosystem.to_s, variables["package_manager"]
      assert_equal "rails", variables["package_name"]
    end
  end

  test "get_package_repo caches the return value" do
    ecosystem = AdvisoryDB.dependency_graph_ecosystem("rubygems")

    VCR.use_cassette("dependency_graph_client_get_package_repo") do
      @client.get_package_repo(package_manager: ecosystem,
        package_name: "rails")
    end

    repo = @client.get_package_repo(package_manager: ecosystem,
      package_name: "rails")
    assert_equal "rails/rails", repo

    WebMock.assert_requested(:post, "https://dependency-graph-api.service.iad.github.net/query", times: 1)
  end

  test "get_package_repo returns nil when package repo is not known" do
    VCR.use_cassette("dependency_graph_client_get_package_repo_no_match") do
      ecosystem = AdvisoryDB.dependency_graph_ecosystem("rubygems")
      repo = @client.get_package_repo(package_manager: ecosystem,
        package_name: "zzz-rails-zzz")
      assert_nil repo
    end
  end

  test "get_package_repo returns nil when client is disabled" do
    @client.stubs(enabled?: false)
    ecosystem = AdvisoryDB.dependency_graph_ecosystem("rubygems")
    repo = @client.get_package_repo(package_manager: ecosystem,
      package_name: "rails")
    assert_nil repo
    WebMock.refute_requested :post, "https://dependency-graph-api.service.iad.github.net/query"
  end

  test "get_estimated_impact returns estimated count for known package" do
    ecosystem = AdvisoryDB.dependency_graph_ecosystem("npm")

    VCR.use_cassette("dependency_graph_client_get_estimated_impact") do
      estimate = @client.get_estimated_impact(
        package_manager: ecosystem,
        package_name: "electron",
        version_range: ">= 14.0.0-beta.1, < 14.2.4",
      )
      assert_equal 1592, estimate
    end

    WebMock.assert_requested(:post, "https://dependency-graph-api-slow-queries.service.iad.github.net/query", times: 1) do |req|
      refute_nil req.headers["X-Request-Hmac"]
      variables = JSON.parse(req.body)["variables"]
      assert_equal ecosystem.to_s, variables["package_manager"]
      assert_equal "electron", variables["package_name"]
      assert_equal ">= 14.0.0-beta.1, < 14.2.4", variables["version_range"]
    end
  end

  test "get_estimated_impact caches the return value" do
    ecosystem = AdvisoryDB.dependency_graph_ecosystem("npm")

    VCR.use_cassette("dependency_graph_client_get_estimated_impact") do
      @client.get_estimated_impact(
        package_manager: ecosystem,
        package_name: "electron",
        version_range: ">= 14.0.0-beta.1, < 14.2.4",
      )
    end

    estimate = @client.get_estimated_impact(
      package_manager: ecosystem,
      package_name: "electron",
      version_range: ">= 14.0.0-beta.1, < 14.2.4",
    )
    assert_equal 1592, estimate

    WebMock.assert_requested(:post, "https://dependency-graph-api-slow-queries.service.iad.github.net/query", times: 1)
  end

  test "get_estimated_impact returns -1 if the query times out" do
    VCR.use_cassette("dependency_graph_client_get_estimated_impact_timeout") do
      ecosystem = AdvisoryDB.dependency_graph_ecosystem("rubygems")
      estimate = @client.get_estimated_impact(
        package_manager: ecosystem,
        package_name: "rails",
        version_range: ">= 6.0.0",
      )
      assert_equal(-1, estimate)
    end
  end

  test "get_estimated_impact returns nil when client is disabled" do
    @client.stubs(enabled?: false)
    ecosystem = AdvisoryDB.dependency_graph_ecosystem("npm")
    estimate = @client.get_estimated_impact(
      package_manager: ecosystem,
      package_name: "electron",
      version_range: ">= 14.0.0-beta.1, < 14.2.4",
    )
    assert_nil estimate
    WebMock.refute_requested :post, "https://dependency-graph-api-slow-queries.service.iad.github.net/query"
  end
end
