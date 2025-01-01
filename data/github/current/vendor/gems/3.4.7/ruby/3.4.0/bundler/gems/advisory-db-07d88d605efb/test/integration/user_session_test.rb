# frozen_string_literal: true

require "test_helper"

class UserSessionTest < ActionDispatch::IntegrationTest
  test "creates a User when request made and User does not pre-exist" do
    login = "defunkt"
    refute User.exists?(login: login)

    get "/", headers: { "X-Okta-Username" => "#{login}@github.com" }

    expected_user = User.find_by(login: login)
    assert expected_user

    assert_equal expected_user, assigns(:current_user)
  end

  test "does not create a user when request made and User already exists" do
    user = create(:user)

    assert_no_changes("User.count") do
      get "/", headers: { "X-Okta-Username" => user.email }
    end
  end

  test "current_user is set to the user making the request" do
    user = create(:user)

    assert_no_changes("User.count") do
      get "/", headers: { "X-Okta-Username" => user.email }
    end

    assert_equal user, assigns(:current_user)
  end

  # unexpected use cases for Okta Network Gateway

  test "returns 403 when the X-Okta-Username header is not set" do
    assert_no_changes("User.count") do
      get "/"
    end
    assert_response :forbidden
  end

  test "returns 403 when the X-Okta-Username is not from github" do
    assert_no_changes("User.count") do
      get "/", headers: { "X-Okta-Username" => "hacker@notgithub.com" }
    end
    assert_response :forbidden
  end
end
