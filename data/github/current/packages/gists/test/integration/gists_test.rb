# typed: strict
# frozen_string_literal: true

require "test_helper"

class ViewingAGistTest < GitHub::IntegrationTestCase
  test "public gists do not display private forks", skip_in_multitenant_mode: true do
    pub_user = create(:user, login: "public-fork-owner")
    parent = create(:gist, public: true, user: pub_user)
    create :gist,
      parent: parent,
      user: pub_user,
      public: true
    create :gist,
      parent: parent,
      user: create(:user, login: "secret-fork-owner"),
      public: false

    as pub_user
    get "/gist/#{parent.name_with_display_owner}/forks"

    assert_response :ok
    assert_match /public-fork-owner/, response.body
    refute_match /secret-fork-owner/, response.body
  end

  test "user access on public gists" do
    user = create(:user, login: "public-fork-owner")
    parent = create(:gist, public: true, user: user)
    create :gist,
      parent: parent,
      user: user,
      public: true

    as user
    get "/gist/#{parent.name_with_display_owner}/forks"

    if TestEnv.test_in_multitenancy_mode?
      # Gists are not available in multi-tenant
      assert_response :not_found
    else
      assert_response :ok
    end
  end
end
