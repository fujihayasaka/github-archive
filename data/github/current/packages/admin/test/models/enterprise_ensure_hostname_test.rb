# typed: true
# frozen_string_literal: true

require "test_helper"
require "github/enterprise/middleware"

class EnterpriseEnsureHostnameTest < Minitest::Test
  include Rack::Test::Methods

  def test_appease_no_test_check
    assert true
  end

  if GitHub.enterprise?
    def app
      Rack::Builder.new do
        use GitHub::Enterprise::Middleware::EnsureHostname
        map "/" do
          run lambda { |_env| [200, { "Content-Type" => "text/plain" }, "OK"] }
        end
      end
    end

    def setup
      @original_host_name = GitHub.host_name
      GitHub.host_name    = "github.example.com"
      @api_hostname       = "api." + GitHub.host_name
      @gist_hostname      = "gist." + GitHub.host_name
    end

    def teardown
      GitHub.host_name = @original_host_name
    end

    def test_redirects_on_unexpected_hostname
      get "/", {}, "SERVER_NAME" => "git", "HTTP_HOST" => "git"

      assert_equal "git", last_request.env["HTTP_HOST"]
      assert_equal 301, last_response.status
      assert_match GitHub.host_name, last_response.location
    end

    def test_redirect_preserves_parameters
      get "/bob", {}, "SERVER_NAME" => "git", "HTTP_HOST" => "git"

      assert_equal "git", last_request.env["HTTP_HOST"]
      assert_equal 301, last_response.status
      assert_match GitHub.host_name + "/bob", last_response.location
    end

    def test_no_redirect_on_expected_hostname
      get "/", {}, "SERVER_NAME" => GitHub.host_name, "HTTP_HOST" => GitHub.host_name

      assert_equal GitHub.host_name, last_request.env["HTTP_HOST"]
      assert_equal 200, last_response.status
    end

    def test_no_redirect_on_api_subdomain
      get "/", {}, "SERVER_NAME" => @api_hostname, "HTTP_HOST" => @api_hostname

      assert_equal @api_hostname, last_request.env["HTTP_HOST"]
      assert_equal 200, last_response.status
    end

    def test_no_redirect_on_gist_subdomain
      get "/", {}, "SERVER_NAME" => @gist_hostname, "HTTP_HOST" => @gist_hostname

      assert_equal @gist_hostname, last_request.env["HTTP_HOST"]
      assert_equal 200, last_response.status
    end

    def test_no_redirect_on_status_check
      get "/status", {}, "SERVER_NAME" => "git", "HTTP_HOST" => "git"
      assert_equal 200, last_response.status
    end
  end
end
