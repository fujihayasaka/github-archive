# typed: true
# frozen_string_literal: true

require "test_helper"

class StafftoolsGistMaintenanceControllerHttpTest < GitHub::IntegrationTestCase
  fixtures do
    @staff = create :staff_admin_user
    @user  = create(:user)

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

  end

  teardown do
    GitRepositoryBlock.expire_country_block_cache
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

      perform_enqueued_jobs(only: GistMaintenanceJob) do
        post stafftools_gist_path(@gist, path_segment: "schedule_maintenance")
      end
      assert_equal "complete", @gist.reload.maintenance_status
    end
  end

  private

  def stafftools_gist_path(gist, path_segment: nil)
    [
      "/stafftools/gist_maintenance/#{gist.id}",
      path_segment,
    ].compact.join("/")
  end
end
