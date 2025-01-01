# typed: true
# frozen_string_literal: true

require "test_helper"

class StacksAppHelperTest < GitHub::TestCase
  fixtures do
    @pub_user = create(:user, login: "public-user")
    @simple_repo = create(:repository, name: "simple-repo", owner: @pub_user)
  end

  context "app_status_endpoint_exists?" do
    test "returns false if app is not present" do
      refute StacksAppHelper.app_status_endpoint_exists?(nil)
    end

    test "returns false if app url is not present" do
      refute StacksAppHelper.app_status_endpoint_exists?({})
    end

    test "returns false if app url is not valid" do
      app = { "url" => "http://invalid.url" }
      refute StacksAppHelper.app_status_endpoint_exists?(app)
    end

    test "return true if app url is valid" do
      app = { "url" => "https://github.com" }
      HTTParty.expects(:get).times(1).returns(stub(code: 200))
      assert StacksAppHelper.app_status_endpoint_exists?(app)
    end

    StacksAppHelper::HTTP_ERRORS.each do |http_error_class|
      test "handles #{http_error_class} exceptions" do
        http_error = http_error_class.new(http_error_class.name)
        app = { "url" => "https://github.com" }
        stub_request(:get, app["url"]).to_raise(http_error)
        refute StacksAppHelper.app_status_endpoint_exists?(app)
      end
    end
  end

  context "app_setup_completed?" do
    test "returns false if app is not present" do
      refute StacksAppHelper.app_setup_completed?(nil, nil)
    end

    test "returns false if app integration is not present" do
      refute StacksAppHelper.app_setup_completed?(nil, {})
    end

    test "returns false if app installation is not present" do
      refute StacksAppHelper.app_setup_completed?(nil, { "integration" => {} })
    end

    test "returns false if repo is not present" do
      app = { "integration" => { "url" => "http://invalid.url" }, "installation" => { "id" => 1 } }
      refute StacksAppHelper.app_setup_completed?(nil, app)
    end

    test "returns false if app url is invalid" do
      app = { "integration" => { "url" => "http://invalid.url" }, "installation" => { "id" => 1 } }
      refute StacksAppHelper.app_setup_completed?(nil, app)
    end

    test "returns false if app status endpoint returns non success status" do
      app = { "integration" => { "url" => "http://invalid.url" }, "installation" => { "id" => 1 } }
      HTTParty.expects(:get).times(1).returns(stub(code: 500))
      refute StacksAppHelper.app_setup_completed?(@simple_repo, app)
    end

    test "returns true if app status endpoint returns success status" do
      app = { "integration" => { "url" => "http://invalid.url" }, "installation" => { "id" => 1 } }
      HTTParty.expects(:get).times(1).returns(stub(code: 200))
      assert StacksAppHelper.app_setup_completed?(@simple_repo, app)
    end

    StacksAppHelper::HTTP_ERRORS.each do |http_error_class|
      test "handles #{http_error_class} exceptions" do
        http_error = http_error_class.new(http_error_class.name)
        app = { "integration" => { "url" => "http://invalid.url" }, "installation" => { "id" => 1 } }
        stub_request(:get, app["integration"]["url"]).to_raise(http_error)
        refute StacksAppHelper.app_setup_completed?(@simple_repo, app)
      end
    end
  end
end
