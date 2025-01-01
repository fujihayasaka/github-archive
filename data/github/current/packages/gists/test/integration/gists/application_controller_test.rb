# typed: true
# frozen_string_literal: true

require "test_helper"

class GistsScopeController < Gists::ApplicationController
  def test
    render plain: "Hello", status: :ok
  end

  def external_conditional_access_policy_enforceable_test
    render json: { external_conditional_access_policy_enforceable: external_conditional_access_policy_enforceable }
  end
end

class GistsApplicationControllerHttpTest < GitHub::IntegrationTestCase
  fixtures do
    @new_user = create :user, created_at: 20.minutes.ago
    @old_user = create :user, created_at: 1.day.ago
  end

  setup_once do
    TestRoutes.draw do
      get "/gists_scope/test", to: "gists_scope#test"
      get "/gists_scope/external_conditional_access_policy_enforceable_test", to: "gists_scope#external_conditional_access_policy_enforceable_test"
    end
  end

  setup do
    GitHub.first_run = false # disable enterprise_first_run?
  end

  teardown_once do
    TestRoutes.clear!
  end

  test "sets a gist key in log data to help with filtering" do
    refute GitHub.enterprise_first_run?, "Expected enterprise_first_run to be false"

    get "/gists_scope/test"

    log_data = @controller.send(:log_data)
    assert log_data[:gist] == true, "Gists controllers should set a gist=true logging flag"
  end

  context "#completed_gist_signup_flow?" do
    test "is true when signed in as a new user and a query param of signup=true" do
      as @new_user
      get "/gists_scope/test", params: { signup: "true" }

      assert @controller.send(:completed_gist_signup_flow?)
    end

    test "is false when signed in as an old user and a query param of signup=true" do
      as @old_user
      get "/gists_scope/test", params: { signup: "true" }

      refute @controller.send(:completed_gist_signup_flow?)
    end

    test "is false when not signed in with a query param of signup=true" do
      get "/gists_scope/test", params: { signup: "true" }

      refute @controller.send(:completed_gist_signup_flow?)
    end

    test "is false when signed in as a new user without a query param of signup=true" do
      as @new_user
      get "/gists_scope/test"

      refute @controller.send(:completed_gist_signup_flow?)
    end
  end

  test "external conditional access policy not enforceable" do
    as @new_user
    get "/gists_scope/external_conditional_access_policy_enforceable_test"
    result = JSON.parse(response.body)["external_conditional_access_policy_enforceable"]
    assert_equal "no", result
  end
end
