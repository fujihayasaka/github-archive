# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/gist_controller_helpers"

class GistsControllerDeleteGistHttpTest < GitHub::IntegrationTestCase
  include GistsControllerTestHelpers
  extend GistsControllerTestSetup

  skip_with_all_emus

  fixtures(&fixtures_block)
  setup(&global_setup_block)

  context "deleting a gist as the owner" do
    test "works" do
      user = create(:user, login: "GistUserPro")
      gist = GistHelpers.generate(user: user,
                           contents: @create_contents)

      as user

      assert_gist_soft_deleted(gist) do
        delete gist_url_for(gist)
      end

      assert_match /successfully/i, flash[:notice]
      assert_redirected_to user_gists_path(user)
    end

    test "increments the destroy dogstats for a user" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      user = create(:user, login: "GistUserPro")
      gist = GistHelpers.generate(user: user,
                           contents: @create_contents)

      as user

      assert_gist_soft_deleted(gist) do
        delete gist_url_for(gist)
      end

      assert_equal 1, GitHub.dogstats.increments("gist.web.destroy", tags: ["reason:deleted_by_user"]).count
    end
  end

  context "attempting gist deletion as a non-owner" do
    test "fails without a matching IP or session" do
      gist = GistHelpers.generate(user: create(:user),
                           contents: @create_contents)

      as create(:user, login: "DeleteCrazy")
      delete gist_url_for(gist)

      assert gist.active?
      assert_response 404
    end

    test "works for a user with a session that includes the Gist" do
      gist = GistHelpers.generate(contents: @create_contents)

      @session = {
        anon_gists: [gist.id.to_s],
      }

      as @pub_user

      assert_gist_soft_deleted(gist) do
        delete gist_url_for(gist)
      end
    end

    test "fails for a user with a session that does not include the Gist" do
      gist = GistHelpers.generate(contents: @create_contents)

      @session = {
        anon_gists: nil,
      }

      as @pub_user

      delete gist_url_for(gist)

      assert gist.active?
      assert_response 404
    end

    unless GitHub.enterprise?
      test "works for a user with an IP that matches the creator" do
        gist = GistHelpers.generate(contents: @create_contents, creator_ip: "1.2.3.4")
        request_env["REMOTE_ADDR"] = "1.2.3.4"

        as @pub_user

        assert_gist_soft_deleted(gist) do
          delete gist_url_for(gist)
        end
      end

      test "fails for a user with an IP that doesn't match the creator" do
        gist = GistHelpers.generate(contents: @create_contents, creator_ip: "1.2.3.4")
        request_env["REMOTE_ADDR"] = "2.3.4.5"

        as @pub_user

        delete gist_url_for(gist)

        assert gist.active?
        assert_response 404
      end
    end
  end

  context "deleting a gist as a staff user" do
    test "staff users cannot delete gists from the main web UI" do
      user = create(:user)
      gist = GistHelpers.generate(user: user,
                           contents: @create_contents)

      as @staff_user

      delete gist_url_for(gist)

      assert gist.active?
    end
  end

  context "deleting a gist as an anonymous user" do
    test "works for the anonymous creator with an active session" do
      gist = GistHelpers.generate(contents: @create_contents)

      @session = {
        anon_gists: [gist.id.to_s],
      }

      assert_gist_soft_deleted(gist) do
        delete gist_url_for(gist)
      end
    end

    test "instruments the deletion for the anonymous creator with an active session" do
      gist = GistHelpers.generate(contents: @create_contents)

      @session = {
        anon_gists: [gist.id.to_s],
      }

      events = subscribe "gist.destroy"
      assert_gist_soft_deleted(gist) do
        delete gist_url_for(gist)
      end

      expected_payload = {
        visibility: "public",
        fork: false,
        actor: nil,
        user: nil,
        gist_id: gist.id,
        gist: gist.name_with_owner,
      }
      assert event = events.pop, "expected an instrumentation event"
      assert_equal expected_payload, event.payload
    end

    test "increments the destroy dogstats for a creator with an active session" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      gist = GistHelpers.generate(contents: @create_contents)

      @session = {
        anon_gists: [gist.id.to_s],
      }

      assert_gist_soft_deleted(gist) do
        delete gist_url_for(gist)
      end

      assert_equal 1, GitHub.dogstats.increments("gist.web.destroy", tags: ["reason:deleted_by_session"]).count
    end

    test "fails for an anonymous user without a valid session or IP" do
      gist = GistHelpers.generate(contents: @create_contents, creator_ip: nil)

      delete gist_url_for(gist)
      assert gist.active?
    end
    unless GitHub.enterprise?
      test "works for the anonymous creator with a matching IP" do
        gist = GistHelpers.generate(contents: @create_contents, creator_ip: "1.2.3.4")
        request_env["REMOTE_ADDR"] = "1.2.3.4"

        assert_gist_soft_deleted(gist) do
          delete gist_url_for(gist)
        end
      end

      test "increments the destroy dogstats for a creator with a matching IP" do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

        gist = GistHelpers.generate(contents: @create_contents, creator_ip: "1.2.3.4")
        request_env["REMOTE_ADDR"] = "1.2.3.4"

        assert_gist_soft_deleted(gist) do
          delete gist_url_for(gist)
        end

        assert_equal 1, GitHub.dogstats.increments("gist.web.destroy", tags: ["reason:deleted_by_ip"]).count
      end

      test "fails for an anonymous user who doesn't have the correct IP" do
        gist = GistHelpers.generate(contents: @create_contents, creator_ip: "1.2.3.4")
        request_env["REMOTE_ADDR"] = "4.5.6.7"

        delete gist_url_for(gist)
        assert gist.active?
      end
    end
  end

  def assert_gist_soft_deleted(gist)
    assert gist.active?

    perform_enqueued_jobs(only: [GistSynchronizeSearchIndexJob]) { yield }
    refute gist.reload.active?
    assert gist.reload.deleted?

    assert_enqueued_with job: RemoveFromSearchIndexJob, args: ["gist", gist.id]
  end
end
