# typed: true
# frozen_string_literal: true

require "test_helper"

class StafftoolsGistsControllerHttpTest < GitHub::IntegrationTestCase
  include HydroTestHelpers

  skip_in_multitenant_mode

  fixtures do
    @staff = create :staff_admin_user
    @user  = create(:user)
    @org = create(:organization)

    @url = "https://github.com/github/dmca/blob/master/2011/2011-01-27-sony.markdown"
    @year_month_url = "https://github.com/github/dmca/blob/master/2018/10/2018-10-04-sony.md"

    setup_staff_user
  end

  setup do
    as @staff
    contents = [{ name: "1", value: "random content" }]
    @gist = GistHelpers.generate contents: contents, user: @user, public: true
    @fork = @gist.fork @staff
    @secret_gist = GistHelpers.generate(contents: contents, user: @user, public: false)

    GitHub.flipper[:darkship_dmca_takedown_skip_for_perfomance_reason].disable
  end

  teardown do
    GitRepositoryBlock.expire_country_block_cache
  end

  # Blocks are dotcom only
  if GitHub.enterprise?
    test "dmcas 404" do
      post stafftools_gist_path(@gist, path_segment: "dmca_takedown"), params: { takedown_url: @url }
      assert_response 404
    end

    test "country blocks 404" do
      post stafftools_gist_path(@gist, path_segment: "country_block"), params: country_block_payload
      assert_response 404
    end
  else
    context "#dmca_takedown" do
      test "processes a DMCA takedown" do
        perform_enqueued_jobs only: [DisableRepositoryAccessJob] do
          post stafftools_gist_path(@gist, path_segment: "dmca_takedown"), params: { takedown_url: @url }
        end
        assert @gist.reload.access.dmca?
      end

      test "sets the takedown URL" do
        perform_enqueued_jobs only: [DisableRepositoryAccessJob] do
          post stafftools_gist_path(@gist, path_segment: "dmca_takedown"), params: { takedown_url: @url }
        end
        assert_equal @url, @gist.reload.access.dmca_url
      end

      test "gives the user confirmation of takedown" do
        post stafftools_gist_path(@gist, path_segment: "dmca_takedown"), params: { takedown_url: @url }
        assert_equal "Takedown processed", flash[:notice]
      end

      test "accepts year/month foldered takedown URLs" do
        perform_enqueued_jobs only: [DisableRepositoryAccessJob] do
          post stafftools_gist_path(@gist, path_segment: "dmca_takedown"), params: { takedown_url: @year_month_url }
        end
        assert @gist.reload.access.dmca?
      end

      test "cannot process a DMCA takedown with invalid URL" do
        post stafftools_gist_path(@gist, path_segment: "dmca_takedown"), params: { takedown_url: "https://rawr.com/bears" }
        refute @gist.reload.access.dmca?
      end

      test "returns a useful error if invalid URL" do
        post stafftools_gist_path(@gist, path_segment: "dmca_takedown"), params: { takedown_url: "https://rawr.com/bears" }
        assert_equal "Invalid takedown notice URL", flash[:error]
      end

      test "requires a payload" do
        post stafftools_gist_path(@gist, path_segment: "dmca_takedown")
        refute @gist.reload.access.dmca?
      end

      test "returns a useful error if no payload" do
        post stafftools_gist_path(@gist, path_segment: "dmca_takedown")
        assert_equal "Invalid takedown notice URL", flash[:error]
      end

      test "processes DMCA takedowns for secret gists" do
        perform_enqueued_jobs only: [DisableRepositoryAccessJob] do
          post stafftools_gist_path(@secret_gist, path_segment: "dmca_takedown"), params: { takedown_url: @url }
        end
        assert @secret_gist.reload.access.dmca?
      end

      test "requires a takedown_url for private gists" do
        post stafftools_gist_path(@secret_gist, path_segment: "dmca_takedown")
        assert_equal "Invalid takedown notice URL", flash[:error]
      end
    end

    context "#dmca_restore" do
      test "removes a DMCA takedown" do
        @gist.access.disable("dmca", @staff, dmca_takedown: @url)
        delete stafftools_gist_path(@gist, path_segment: "dmca_takedown")
        refute @gist.reload.access.dmca?
      end

      test "confirms removal for the user" do
        @gist.access.disable("dmca", @staff, dmca_takedown: @url)
        delete stafftools_gist_path(@gist, path_segment: "dmca_takedown")
        assert_equal "Takedown removed", flash[:notice]
      end
    end

    context "#country_block" do
      test "processes a country block" do
        events = subscribe "staff.country_block"

        expected_payload = {
          user: @gist.owner.login,
          block: country_block_payload[:country_block],
          reason: country_block_payload[:country_block_reason]
        }

        post stafftools_gist_path(@gist, path_segment: "country_block"), params: country_block_payload
        assert @gist.reload.access.country_block?("RU")
        assert_includes flash[:notice], "Country block processed"
        assert event = events.pop, "staff.country_block event was expected"
        assert_subset_hash expected_payload, event.payload
      end

      test "requires a payload" do
        post stafftools_gist_path(@gist, path_segment: "country_block")
        refute @gist.reload.access.country_block?("RU")
      end

      test "returns a useful error if no payload" do
        post stafftools_gist_path(@gist, path_segment: "country_block")
        assert_equal "invalid country block", flash[:error]
      end

      test "does not block a secret gist" do
        post stafftools_gist_path(@secret_gist, path_segment: "country_block"), params: country_block_payload
        refute @secret_gist.reload.access.country_block?("RU")
      end

      test "returns a useful error on a secret gist" do
        post stafftools_gist_path(@secret_gist, path_segment: "country_block"), params: country_block_payload
        assert_equal "can not country block a private gist", flash[:error]
      end
    end

    test "removes a country block" do
      @gist.access.country_block(@staff, GitRepositoryBlock::RUSSIAN_INTERNET_BLOCKLIST, @url, "Reason for Russian Internet Blocklist")

      delete stafftools_gist_path(@gist, path_segment: "country_block"), params: { country_block: GitRepositoryBlock::RUSSIAN_INTERNET_BLOCKLIST }

      refute @gist.reload.access.country_block?("RU")
      assert_includes flash[:notice], "Country block removed"
    end
  end

  context "#deleted" do
    test "404s for deleted org" do
      GitHub.flipper[:stafftools_hide_deleted_organization].enable
      GitHub.flipper[:soft_delete_organization].enable
      @org.soft_delete!(@staffer)
      assert_predicate @org, :deleted?

      get "/stafftools/users/#{@org.display_login}/gists/deleted"

      assert_response :not_found
    end

    test "finds deleted public gists for this user" do
      @gist.remove(async: true)

      get "/stafftools/users/#{@user.display_login}/gists/deleted"
      assert_equal @user, @gist.user

      assert_template "stafftools/gists/deleted"
      assert_select "#stafftools a[href='/stafftools/users/#{@user.display_login}/gists/#{@gist.repo_name}']"
      assert_includes response.body, "last updated at #{@gist.updated_at.in_time_zone}"
    end

    test "find deleted secret gists" do
      @secret_gist.remove(async: true)

      get "/stafftools/users/#{@user.display_login}/gists/deleted"
      assert_equal @user, @secret_gist.user

      assert_template "stafftools/gists/deleted"
      assert_select "#stafftools a[href='/stafftools/users/#{@user.display_login}/gists/#{@secret_gist.repo_name}']", true
      assert_includes response.body, "last updated at #{@secret_gist.updated_at.in_time_zone}"
    end
  end

  context "#index" do
    test "user owned gists are viewable" do
      get stafftools_user_gists_path(@user)
      assert_response :ok
    end

    test "user owned gists are viewable with unrouted gists" do
      GitHub::DGit::Delegate.any_instance.stubs(:healthy_replicas).raises(GitHub::DGit::UnroutedError.new("💥"))
      get stafftools_user_gists_path(@user)
      assert_response :ok
    end

    test "404s for deleted org" do
      GitHub.flipper[:stafftools_hide_deleted_organization].enable
      GitHub.flipper[:soft_delete_organization].enable
      @org.soft_delete!(@staffer)
      assert_predicate @org, :deleted?

      get stafftools_user_gists_path(@org)

      assert_response :not_found
    end
  end

  context "#show" do
    test "user owned gists are viewable" do
      get stafftools_gist_path(@gist)
      assert_response :ok
    end


    test "user owned gists are viewable with unrouted gists" do
      GitHub::DGit::Delegate.any_instance.stubs(:healthy_replicas).raises(GitHub::DGit::UnroutedError.new("💥"))
      get stafftools_user_gists_path(@user)
      assert_response :ok
    end

    test "anonymous gists are viewable" do
      @gist.update_column :user_id, nil
      assert @gist.anonymous?

      get stafftools_gist_path(@gist)
      assert_response :ok
    end

    test "deleted gists are viewable" do
      @secret_gist.remove async: false
      refute Gist.active.exists?(id: @secret_gist.id)

      get stafftools_gist_path(@secret_gist)
      assert_response :ok

      assert_includes response.body, "Restore this gist"
    end

    test "doesn't blow up when showing a fork with a missing parent" do
      @fork.parent.delete

      get stafftools_gist_path(@fork)
      assert_response :ok
    end

    test "staff users can block archive download" do
      refute @gist.archive_resource_blocked?
      post stafftools_gist_path(@gist, path_segment: "block_archive_download")
      assert_response 302
      @gist.reload
      assert @gist.archive_resource_blocked?
    end

    test "staff users can unblock archive download" do
      @gist.block_archive_resource(actor: @gist.owner)
      assert @gist.archive_resource_blocked?
      post stafftools_gist_path(@gist, path_segment: "unblock_archive_download")
      assert_response 302
      @gist.reload
      refute @gist.archive_resource_blocked?
    end
  end

  context "#restore" do
    test "restores the gist" do
      @gist.remove(async: false)
      refute Gist.active.exists?(id: @gist.id)

      post stafftools_gist_path(@gist, path_segment: "restore")

      assert Gist.exists?(id: @gist.id)
    end

    test "redirects when restoring an active gist" do
      assert Gist.active.exists?(id: @gist.id)

      post stafftools_gist_path(@gist, path_segment: "restore")

      assert_redirected_to "http://github.com"
    end

    test "restores an anonymous gist" do
      @gist.update_column :user_id, nil
      assert @gist.anonymous?
      @gist.remove(async: false)
      refute Gist.active.exists?(id: @gist.id)

      post stafftools_gist_path(@gist, path_segment: "restore")

      assert Gist.exists?(id: @gist.id)
    end

    test "instruments the restore" do
      @gist.remove(async: false)
      events = subscribe "staff.restore_gist"
      post stafftools_gist_path(@gist, path_segment: "restore")

      if GitHub.guard_audit_log_staff_actor?
        expected_payload = {
          gist: @gist.name_with_owner,
          gist_id: @gist.id,
          user: @gist.owner.to_s,
          user_id: @gist.owner.id,
          staff_actor: @staff.to_s,
          staff_actor_id: @staff.id,
          actor: User.staff_user.to_s,
          actor_id: User.staff_user.id,
          visibility: @gist.event_payload_visibility,
          fork: @gist.fork?,
        }
      else
        expected_payload = {
          gist: @gist.name_with_owner,
          gist_id: @gist.id,
          user: @gist.owner.to_s,
          user_id: @gist.owner.id,
          actor: @staff.to_s,
          actor_id: @staff.id,
          visibility: @gist.event_payload_visibility,
          fork: @gist.fork?,
        }
      end

      assert event = events.pop, "an event was expected"
      assert_equal "staff.restore_gist", event.name
      assert_equal expected_payload, event.payload
      assert_nil events.pop, "an event was not expected"
    end
  end

  context "#destroy" do
    test "destroys the gist" do
      assert @gist.active?

      delete stafftools_gist_path(@gist), params: { tos_reason: "TRADEMARK", content_formats: ["TEXT"], source: "USER_REPORT" }
      assert Gist.deleted.exists?(id: @gist.id)
    end

    test "destroy an anonymous gist" do
      assert @gist.active?
      @gist.update_column :user_id, nil
      assert @gist.anonymous?

      delete stafftools_gist_path(@gist), params: { tos_reason: "TRADEMARK", content_formats: ["TEXT"], source: "USER_REPORT" }
      assert Gist.deleted.exists?(id: @gist.id)
    end

    test "instruments the destroy" do
      events = subscribe "staff.delete_gist"
      delete stafftools_gist_path(@gist), params: { tos_reason: "TRADEMARK", content_formats: ["TEXT"], source: "USER_REPORT" }

      if GitHub.guard_audit_log_staff_actor?
        expected_payload = {
          gist: @gist.name_with_owner,
          gist_id: @gist.id,
          user: @gist.owner.to_s,
          user_id: @gist.owner.id,
          staff_actor: @staff.to_s,
          staff_actor_id: @staff.id,
          actor: User.staff_user.to_s,
          actor_id: User.staff_user.id,
          visibility: @gist.event_payload_visibility,
          fork: @gist.fork?,
        }
      else
        expected_payload = {
          gist: @gist.name_with_owner,
          gist_id: @gist.id,
          user: @gist.owner.to_s,
          user_id: @gist.owner.id,
          actor: @staff.to_s,
          actor_id: @staff.id,
          visibility: @gist.event_payload_visibility,
          fork: @gist.fork?,
        }
      end

      assert event = events.pop, "an event was expected"
      assert_equal "staff.delete_gist", event.name
      assert_equal expected_payload, event.payload
      assert_nil events.pop, "an event was not expected"
    end

    test "publishes ModerationAction event for a test staff.delete_gist action to hydro" do
      @staff.update!(email: "mona@github.com")
      test_user = create(:user, email: "mona+evil@github.com")
      @gist.update_attribute(:user, test_user)
      Timecop.freeze do
        as @staff
        delete stafftools_gist_path(@gist), params: { tos_reason: "TRADEMARK", content_formats: ["TEXT"], source: "USER_REPORT" }
        @gist.reload
        assert_hydro_published({
          action: "staff.delete_gist",
          actor: Hydro::EntitySerializer.user(@staff),
          is_test: true,
          content_moderation: {
            global_relay_id: @gist.global_relay_id,
            content_type: "gist",
            content: @gist.url,
            content_created_at: @gist.created_at,
            content_updated_at: @gist.updated_at,
            end_timestamp: nil,
            moderation_types: [:REMOVED],
            formats: [:TEXT]
          },
          reason: :REASON_UNKNOWN,
          tos_reason: :TRADEMARK,
          source: :USER_REPORT
        }, schema: "github.moderation.v0.ModerationAction")
      end
    end
  end

  context "#mark_as_broken" do
    test "changes maintenance status to broken" do
      post stafftools_gist_path(@gist, path_segment: "mark_as_broken")
      assert_equal "broken", @gist.reload.maintenance_status
    end
  end

  context "#schedule_maintenance" do
    test "enqueues a maintenance job for the gist" do
      assert_enqueued_with job: GistMaintenanceJob, args: [@gist.id], queue: @gist.maintenance_queue_name.value! do
        post stafftools_gist_path(@gist, path_segment: "schedule_maintenance")
      end
    end

    test "enqueues a maintenance job even if the gist is marked broken" do
      @gist.mark_as_broken
      assert_equal "broken", @gist.maintenance_status

      perform_enqueued_jobs only: [GistMaintenanceJob] do
        post stafftools_gist_path(@gist, path_segment: "schedule_maintenance")
      end
      assert_equal "complete", @gist.reload.maintenance_status
    end
  end

  private

  def stafftools_gist_path(gist, path_segment: nil)
    [
      "/stafftools/users/#{gist.user_param}/gists/#{gist.to_param}",
      path_segment,
    ].compact.join("/")
  end

  def stafftools_user_gists_path(user, path_segment: nil)
    [
      "/stafftools/users/#{user.to_param}/gists",
      path_segment,
    ].compact.join("/")
  end

  def country_block_payload(url: @url)
    {
      country_block: GitRepositoryBlock::RUSSIAN_INTERNET_BLOCKLIST,
      country_block_url: url,
      country_block_reason: "Reason for Russian Internet Blocklist",
    }
  end
end
