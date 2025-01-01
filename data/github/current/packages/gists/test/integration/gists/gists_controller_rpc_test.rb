# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/gist_controller_helpers"

class GistsControllerRpcHttpTest < GitHub::IntegrationTestCase
  include GistsControllerTestHelpers
  extend GistsControllerTestSetup

  skip_with_all_emus

  setup do
    GitHub.flipper[:notifications_async_gist_subscription_button].disable
  end

  fixtures(&fixtures_block)
  setup(&global_setup_block)

  context "stars for gist" do
    test "star your own gist" do
      as @pub_user

      assert_difference "@pub_user.starred_gists.count", +1 do
        post gist_url_for(@pub_gist, path_segment: "star")
      end

      assert_redirected_to gist_url_for(@pub_gist)
    end

    test "unstar your own gist" do
      as @pub_user

      post gist_url_for(@pub_gist, path_segment: "star")
      assert_difference "@pub_user.starred_gists.count", -1 do
        post gist_url_for(@pub_gist, path_segment: "unstar")
      end

      assert_redirected_to gist_url_for(@pub_gist)
    end

    test "star someone else's gist" do
      as @priv_user

      assert_difference "@priv_user.starred_gists.count", +1 do
        post gist_url_for(@pub_gist, path_segment: "star")
      end

      assert_redirected_to gist_url_for(@pub_gist)
    end

    test "unstar someone else's gist" do
      as @priv_user

      post gist_url_for(@pub_gist, path_segment: "star")
      assert_difference "@priv_user.starred_gists.count", -1 do
        post gist_url_for(@pub_gist, path_segment: "unstar")
      end

      assert_redirected_to gist_url_for(@pub_gist)
    end
  end

  context "#archive" do
    test "redirects to codeload for secret gist" do
      as @pub_user

      gist_id = @secret_gist.gist_id
      file_oid = @secret_gist.files.first.oid

      get "/gist/#{@secret_gist.owner}/#{gist_id}/archive/#{file_oid}.zip"

      assert_redirected_to_url "#{GitHub.urls.codeload_url}/gist/#{gist_id}/zip/#{file_oid}"
    end
  end

  context "forking a gist" do
    test "shows the fork button on anon gists when you're logged in" do
      # Set Gist as anonymous
      @pub_gist.update_column :user_id, nil

      if GitHub.flipper[:notifyd_primary_gist].enabled?
        setup_notifyd_mocks(@pub_user, @pub_gist)
      end

      as @pub_user
      get gist_url_for(@pub_gist)
      assert_select "button#gist-fork-button" do
        assert_includes response.body, "Fork"
      end

      assert_difference "@pub_gist.forks.reload.count", +1 do
        post gist_url_for(@pub_gist, path_segment: "fork")
      end

      assert_response 302
    end

    test "creates a fork when the current user isn't the gist owner" do
      refute_equal @pub_gist.owner, @priv_user

      if GitHub.flipper[:notifyd_primary_gist].enabled?
        setup_notifyd_mocks(@priv_user, @pub_gist)
      end

      as @priv_user

      get gist_url_for(@pub_gist)
      assert_select "button#gist-fork-button" do
        assert_includes response.body, "Fork"
      end

      assert_difference "@pub_gist.forks.reload.count", +1 do
        post gist_url_for(@pub_gist, path_segment: "fork")
      end

      assert_response 302
    end

    test "doesn't create a fork when the current user is the owner" do
      owner_user = create(:verified_user)
      as owner_user

      user_gist = GistHelpers.generate(
        user: owner_user,
        contents: [{ name: "toppings.txt", value: "Made from fruit" }],
        description: "Jelly"
      )

      if GitHub.flipper[:notifyd_primary_gist].enabled?
        setup_notifyd_mocks(owner_user, user_gist)
      end

      get gist_url_for(user_gist)
      refute_select "button", text: "Fork"

      assert_no_difference "user_gist.forks.count" do
        post gist_url_for(user_gist, path_segment: "fork")
      end

      assert_response 302
    end

    if GitHub.email_verification_enabled?
      test "doesn't create a fork when the current user doesn't have a verified email" do
        @priv_user.emails.each(&:unverify!)

        # Setup that ensures that a user is forced to verify their email
        # This is a distinct check from GitHub.email_verification_enabled?
        GitHub.stubs(:mandatory_email_verification_enabled?).returns(true)
        @priv_user.require_email_verification!

        if GitHub.flipper[:notifyd_primary_gist].enabled?
          setup_notifyd_mocks(@priv_user, @pub_gist)
        end

        as @priv_user

        get gist_url_for(@pub_gist)
        assert_no_difference "@pub_gist.forks.reload.count" do
          post gist_url_for(@pub_gist, path_segment: "fork")
        end

        assert_redirected_to gist_url_for(@pub_gist)
      end
    else
      test "creates a fork when the current user doesn't have a verified email" do
        @priv_user.emails.each(&:unverify!)

        # Setup that ensures that a user is forced to verify their email
        # This is a distinct check from GitHub.email_verification_enabled?
        GitHub.stubs(:mandatory_email_verification_enabled?).returns(true)
        @priv_user.require_email_verification!

        if GitHub.flipper[:notifyd_primary_gist].enabled?
          setup_notifyd_mocks(@priv_user, @pub_gist)
        end

        as @priv_user

        get gist_url_for(@pub_gist)
        assert_difference "@pub_gist.forks.reload.count", +1 do
          post gist_url_for(@pub_gist, path_segment: "fork")
        end

        assert_response 302
      end
    end
  end
end
