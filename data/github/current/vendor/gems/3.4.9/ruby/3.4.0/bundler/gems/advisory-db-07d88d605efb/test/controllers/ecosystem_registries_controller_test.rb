# frozen_string_literal: true

require "test_helper"

class EcosystemRegistriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user)
  end

  test "Fetches a pacakge url for npm" do
    package = "ssl"
    package_url = "https://www.npmjs.com/package/#{package}"
    AdvisoryDBToolkit::Ecosystems::NPM.stubs(:get_package_url).returns(package_url)

    get package_link_ecosystem_registries_url,
      headers: { "X-Okta-Username" => @user.email },
      params: { ecosystem: "npm", package_name: package }

    assert_response :ok
    data = response.parsed_body
    assert_equal package_url, data["package_url"]
    assert_equal 200, data["status"]
    assert_nil data["error"]
  end

  test "package_link caches pacakge url" do
    package = "ssl"
    package_url = "https://www.npmjs.com/package/#{package}"
    VCR.use_cassette("ecosystems_registries_npm_ssl_package") do
      get package_link_ecosystem_registries_url,
        headers: { "X-Okta-Username" => @user.email },
        params: { ecosystem: "npm", package_name: package }
    end

    get package_link_ecosystem_registries_url,
      headers: { "X-Okta-Username" => @user.email },
      params: { ecosystem: "npm", package_name: package }

    assert_response :ok
    data = response.parsed_body
    assert_equal package_url, data["package_url"]
    assert_equal 200, data["status"]
    assert_nil data["error"]

    WebMock.assert_requested(:get, "https://registry.npmjs.org/#{package}", times: 1)
  end

  test "package_link strips leading and trailing whitespace in package_name" do
    package = "ssl"
    package_url = "https://www.npmjs.com/package/#{package}"
    VCR.use_cassette("ecosystems_registries_npm_ssl_package") do
      get package_link_ecosystem_registries_url,
        headers: { "X-Okta-Username" => @user.email },
        params: { ecosystem: "npm", package_name: "  #{package}   " }
    end

    assert_response :ok
    data = response.parsed_body
    assert_equal package_url, data["package_url"]
    assert_equal 200, data["status"]
    assert_nil data["error"]

    WebMock.assert_requested(:get, "https://registry.npmjs.org/#{package}", times: 1)
  end

  test "package_link rescues from InvalidURIError" do
    get package_link_ecosystem_registries_url,
      headers: { "X-Okta-Username" => @user.email },
      params: { ecosystem: "rubygems", package_name: "has space" }

    assert_response :ok
    data = response.parsed_body
    assert_nil data["package_url"]
    assert_equal 400, data["status"]
    assert_equal "Invalid Package", data["error"]
  end

  test "Returns nil package_url if a url is not found" do
    AdvisoryDBToolkit::Ecosystems::NPM.stubs(:get_package_url).returns(nil)

    get package_link_ecosystem_registries_url,
      headers: { "X-Okta-Username" => @user.email },
      params: { ecosystem: "npm", package_name: "ssl" }

    assert_response :ok
    data = response.parsed_body
    assert_nil data["package_url"]
    assert_equal 200, data["status"]
    assert_nil data["error"]
  end

  test "Returns an error when an unexpected ecosystem is queried" do
    get package_link_ecosystem_registries_url,
      headers: { "X-Okta-Username" => @user.email },
      params: { ecosystem: "unavailableEcosystem", package_name: "ssl" }

    assert_response :ok
    data = response.parsed_body
    assert_nil data["package_url"]
    assert_equal 200, data["status"]
    assert_equal "Unsupported ecosystem", data["error"]
  end

  test "Returns an error when an ecosystem api error is encountered" do
    api_response = stub(
      status: 400,
      body: { errors: [{ message: "Unauthorized" }] },
    )
    exception = AdvisoryDBToolkit::Ecosystems::Exceptions::ApiError.new("npm API error", response: api_response)
    AdvisoryDBToolkit::Ecosystems::NPM.stubs(:get_package_url).raises(exception)

    get package_link_ecosystem_registries_url,
      headers: { "X-Okta-Username" => @user.email },
      params: { ecosystem: "npm", package_name: "ssl" }

    assert_response :ok
    data = response.parsed_body
    assert_nil data["package_url"]
    assert_equal 400, data["status"]
    assert_equal "npm API error", data["error"]
  end
end
