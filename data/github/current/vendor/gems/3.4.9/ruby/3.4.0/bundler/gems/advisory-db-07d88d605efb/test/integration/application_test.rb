# frozen_string_literal: true

require "test_helper"

class ApplicationTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user)
  end

  test "theming is set as expected" do
    get "/advisory_reviews", headers: { "X-Okta-Username" => @user.email }

    assert_select "body[data-color-mode=auto]", 1

    @user.color_mode = "dark"
    @user.save!

    get "/advisory_reviews", headers: { "X-Okta-Username" => @user.email }

    assert_select "body[data-color-mode=dark]", 1
  end
end
