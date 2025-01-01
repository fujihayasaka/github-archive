# typed: true
# frozen_string_literal: true

require "test_helper"

class DatabaseSelectionTest < GitHub::TestCase
  self.these_tests_are_order_dependent_and_yearn_to_be_random

  class SuccessApp
    def call(env)
      [200, {}, ""]
    end
  end

  class WritingApp
    def call(env)
      # Perform a write
      login = "foo-#{rand(9999999999)}"
      User.insert({ login: login, display_login: login })

      [200, {}, ""]
    end
  end

  class FailApp
    def call(env)
      # Fails and makes no writes
      [500, {}, ""]
    end
  end

  setup do
    @success_app = Api::Middleware::DatabaseSelection.new(SuccessApp.new)
    @writing_app = Api::Middleware::DatabaseSelection.new(WritingApp.new)
    @fail_app    = Api::Middleware::DatabaseSelection.new(FailApp.new)
    enable_cache_storage
  end

  teardown do
    reset_cache
    disable_cache_storage
  end

  test "does not set timestamp for read-only requests" do
    token = "token random"
    env = Rack::MockRequest.env_for("/", "HTTP_AUTHORIZATION" => token)
    resp = @success_app.call(env)
    assert_equal Time.at(0),
      DatabaseSelector::LastOperations.from_token(token).last_write_timestamp
  end

  test "does not set timestamp for graphql requests" do
    token = "token random"
    env = Rack::MockRequest.env_for("/graphql", "REQUEST_METHOD" => "POST", "HTTP_AUTHORIZATION" => token)
    _resp = @success_app.call(env)
    assert_equal Time.at(0),
      DatabaseSelector::LastOperations.from_token(token).last_write_timestamp
  end

  test "sets timestamp for authenticated write requests" do
    now = Time.at(Time.now.to_i)
    Timecop.freeze(now) do
      tokens = ["token random1", "bearer random2", "oauth2 random3"]
      tokens.each do |token|
        scheme, value = token.split(" ")
        env = Rack::MockRequest.env_for("/", "REQUEST_METHOD" => "POST", "HTTP_AUTHORIZATION" => token)
        resp = GitHub::MysqlInstrumenter.with_instrument_and_track do
          @writing_app.call(env)
        end
        assert_equal now,
          DatabaseSelector::LastOperations.from_token(value).last_write_timestamp
      end
    end
  end

  test "sets timestamp for authenticated token write requests that use basic auth" do
    now = Time.at(Time.now.to_i)
    Timecop.freeze(now) do
      # Since basic auth could contain user passwords, only values that look
      # like legit tokens are treated as tokens by `Api::RequestCredentials`
      access_token = "aa" * 20
      token_basic_auth = Base64::strict_encode64("user:#{access_token}")
      env = Rack::MockRequest.env_for("/", "REQUEST_METHOD" => "POST", "HTTP_AUTHORIZATION" => "basic #{token_basic_auth}")
      resp = GitHub::MysqlInstrumenter.with_instrument_and_track do
        @writing_app.call(env)
      end
      refute_equal access_token, token_basic_auth
      assert_equal Time.at(0),
        DatabaseSelector::LastOperations.from_token(token_basic_auth).last_write_timestamp
      assert_equal now,
        DatabaseSelector::LastOperations.from_token(access_token).last_write_timestamp
    end
  end

  test "sets timestamp for authenticated login and password write requests that use basic auth" do
    now = Time.at(Time.now.to_i)
    Timecop.freeze(now) do
      password_basic_auth = Base64::strict_encode64("user:password")
      env = Rack::MockRequest.env_for("/", "REQUEST_METHOD" => "POST", "HTTP_AUTHORIZATION" => "basic #{password_basic_auth}")
      resp = GitHub::MysqlInstrumenter.with_instrument_and_track do
        @writing_app.call(env)
      end
      refute_equal "password", password_basic_auth
      assert_equal Time.at(0),
        DatabaseSelector::LastOperations.from_token(password_basic_auth).last_write_timestamp
      assert_equal Time.at(0),
        DatabaseSelector::LastOperations.from_token("user:password").last_write_timestamp
      assert_equal now,
        DatabaseSelector::LastOperations.from_creds("user").last_write_timestamp
    end
  end

  test "does not set timestamp for failed read-only request" do
    token = "token random"
    env = Rack::MockRequest.env_for("/", "HTTP_AUTHORIZATION" => token)
    resp = @fail_app.call(env)
    assert_equal Time.at(0),
      DatabaseSelector::LastOperations.from_token(token).last_write_timestamp
  end

  test "does not set timestamp for failed write request" do
    token = "token random"
    env = Rack::MockRequest.env_for("/", "REQUEST_METHOD" => "POST", "HTTP_AUTHORIZATION" => token)
    resp = @fail_app.call(env)
    assert_equal Time.at(0),
      DatabaseSelector::LastOperations.from_token(token).last_write_timestamp
  end

  test "database selector can write and read cache from tokens" do
    token = "token random"
    last_operations = DatabaseSelector::LastOperations.from_token(token)

    assert_empty last_operations.last_writes

    last_operations.store_latest_writes

    refute_empty last_operations.last_writes
    refute_empty DatabaseSelector::LastOperations.from_token(token).last_writes
  end

  test "database selector can write and read cache from login" do
    login = "user"
    last_operations = DatabaseSelector::LastOperations.from_creds(login)

    assert_empty last_operations.last_writes

    last_operations.store_latest_writes

    refute_empty last_operations.last_writes
    refute_empty DatabaseSelector::LastOperations.from_creds(login).last_writes
  end
end
