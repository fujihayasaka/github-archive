# typed: true
# frozen_string_literal: true

require "test_helper"

class ApiMiddlewareLoadSheddingTest < GitHub::TestCase
  include DogstatsTestHelpers

  setup do
    @app = Api::Middleware::LoadShedding.new(->(_) { [200, {}, ["Ok!\n"]] })
  end

  test "tags stats with operation when present" do
    response = @app.call({ "github.api.route" => "GET /route" })

    assert_equal [200, {}, ["Ok!\n"]], response
    assert_dogstats_increment 1, "api.internal.loadshedding", tags: [
      "status:200",
      "timeout_set:false",
      "client_name:unknown",
      "operation:GET /route",
      "traffic:other",
    ]
  end

  test "tags stats as a graphql request when matching" do
    response = @app.call({ "PATH_INFO" => "/graphql" })

    assert_equal [200, {}, ["Ok!\n"]], response
    assert_dogstats_increment 1, "api.internal.loadshedding", tags: [
      "status:200",
      "timeout_set:false",
      "client_name:unknown",
      "operation:unknown",
      "traffic:graphql",
    ]
  end

  test "tags stats graphql with client and operation name when present in env" do
    response = @app.call(
      {
        "PATH_INFO" => "/graphql",
        "github.graphql.client_name" => "hubot-pro",
        "github.graphql.operation_name" => "fetchAllTheThings"
      }
    )

    assert_equal [200, {}, ["Ok!\n"]], response
    assert_dogstats_increment 1, "api.internal.loadshedding", tags: [
      "status:200",
      "timeout_set:false",
      "client_name:hubot-pro",
      "operation:fetchAllTheThings",
      "traffic:graphql",
    ]
  end

  test "tags stats with twirp client name when present" do
    response = @app.call(
      {
        "HTTP_REQUEST_HMAC" => Api::App.request_hmac(Time.now, "allowedhmac"),
        "PATH_INFO" => "/api/internal/twirp/package.Service/Method",
      }
    )

    assert_equal [200, {}, ["Ok!\n"]], response
    assert_dogstats_increment 1, "api.internal.loadshedding", tags: [
      "status:200",
      "timeout_set:false",
      "client_name:allowed",
      "operation:unknown",
      "traffic:twirp",
    ]
  end

  test "tags stats with internal api (non-twirp) client name when present" do
    response = @app.call(
      {
        "PATH_INFO" => "/api/internal/repositories/12345",
        :internal_client_id => "internal-api-client"
      }
    )

    assert_equal [200, {}, ["Ok!\n"]], response
    assert_dogstats_increment 1, "api.internal.loadshedding", tags: [
      "status:200",
      "timeout_set:false",
      "client_name:internal-api-client",
      "operation:unknown",
      "traffic:api_internal",
    ]
  end

  test "returns a 200 with no timeout set" do
    response = @app.call({})

    assert_equal [200, {}, ["Ok!\n"]], response
    assert_dogstats_increment 1, "api.internal.loadshedding", tags: [
      "status:200",
      "timeout_set:false",
      "client_name:unknown",
      "operation:unknown",
      "traffic:other",
    ]
  end

  test "returns a 200 with a timeout set but not expired request, ignoring the old shedding enabled header" do
    Time.stubs(:now).returns(Time.at(1123))
    Process.stubs(:clock_gettime).returns(1123.0)

    response = @app.call(
      {
        "HTTP_X_LOAD_SHEDDING_ENABLED" => "true",
        "HTTP_X_CLIENT_TIMEOUT_MS" => "1000",
        "HTTP_X_NGINX_REQUEST_START" => "t=1123.0",
      }
    )

    assert_equal [200, {}, ["Ok!\n"]], response
    assert_dogstats_increment 1, "api.internal.loadshedding", tags: [
      "status:200",
      "timeout_set:true",
      "client_name:unknown",
      "operation:unknown",
      "traffic:other",
    ]
  end

  test "returns a 200 with a timeout set but not expired request" do
    Time.stubs(:now).returns(Time.at(1123))
    Process.stubs(:clock_gettime).returns(1123.0)

    response = @app.call(
      {
        "HTTP_X_CLIENT_TIMEOUT_MS" => "1000",
        "HTTP_X_NGINX_REQUEST_START" => "t=1123.0",
      }
    )

    assert_equal [200, {}, ["Ok!\n"]], response
    assert_dogstats_increment 1, "api.internal.loadshedding", tags: [
      "status:200",
      "timeout_set:true",
      "client_name:unknown",
      "operation:unknown",
      "traffic:other",
    ]
  end

  test "returns a 503 with an expired request" do
    Time.stubs(:now).returns(Time.at(1123))
    Process.stubs(:clock_gettime).returns(1123.0)

    response = @app.call(
      {
        "HTTP_X_CLIENT_TIMEOUT_MS" => "1000",
        "HTTP_X_NGINX_REQUEST_START" => "t=1121.9",
      }
    )

    assert_equal [
      503,
      { "Content-Type" => "text/plain" },
      ["The server is currently unable to handle this request due to a temporary overload.\n"]
    ], response

    assert_dogstats_increment 1, "api.internal.loadshedding", tags: [
      "timeout_set:true",
      "client_name:unknown",
      "operation:unknown",
      "status:503",
      "traffic:other",
    ]
  end
end
