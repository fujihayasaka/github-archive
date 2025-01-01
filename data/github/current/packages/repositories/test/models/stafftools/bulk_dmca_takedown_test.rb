# typed: true
# frozen_string_literal: true

require "test_helper"

class StafftoolsBulkDmcaTakedownTest < GitHub::TestCase
  RepoMock = Struct.new(:disable_access_job_status, :access)
  fixtures do
    @repos = create_list :repository, 3
    @staff = create :staff_admin_user
    @url = "https://github.com/github/dmca/blob/master/2011/2011-01-27-sony.markdown"
    @valid_takedown = Stafftools::BulkDmcaTakedown.create({ repositories: @repos, disabling_user: @staff, notice_public_url: @url })
    @text =
      <<~HEREDOC
        #{@repos[0].http_url.chomp('.git')}/blob/xxx/README.md
        #{@repos[1].http_url.chomp('.git')}/blob/xxx/SECRET.md
        #{@repos[2].http_url.chomp('.git')}/blob/xxx/README.md
      HEREDOC
  end

  setup do
    GitHub.flipper[:darkship_dmca_takedown_skip_for_perfomance_reason].disable
  end

  test "has a list of repos and a disabling user" do
    assert_equal @repos.length, @valid_takedown.repositories.length
    assert_equal @staff, @valid_takedown.disabling_user
  end

  test "limits number of repos" do
    Stafftools::BulkDmcaTakedown.stub_const(:MAX_REPOS, 5) do
      too_many_repos = create_list :repository, Stafftools::BulkDmcaTakedown::MAX_REPOS + 1
      batch = Stafftools::BulkDmcaTakedown.new({ repositories: too_many_repos, disabling_user: @staff, notice_public_url: @url })

      refute batch.valid?
      refute_nil batch.errors[:number_of_repos_cannot_exceed_max]
    end
  end

  test "processes dmcas" do
    assert_enqueued_jobs @repos.size, only: DisableRepositoryAccessJob do
      @valid_takedown.execute
    end
  end


  test "validates for the presence of repos" do
    batch = Stafftools::BulkDmcaTakedown.new({ disabling_user: @staff, notice_public_url: @url })

    refute batch.valid?
    refute_nil batch.errors[:repositories]
  end

  test "validates for the presence of a takedown url" do
    batch = Stafftools::BulkDmcaTakedown.new({ repositories: @repos, disabling_user: @staff })

    refute batch.valid?
    refute_nil batch.errors[:notice_public_url]
  end

  test "validate the takedown url format" do
    bad_url = "https://github.com/github/dmca/blob/master/hello/2011-01-27-sony.markdown"
    bad_url_2 = "https://github.com/github/dmca/blob/master/2011/sony.markdown"

    assert @valid_takedown.valid?

    @valid_takedown.notice_public_url = bad_url

    refute @valid_takedown.valid?
    refute_nil @valid_takedown.errors[:notice_public_url]

    @valid_takedown.notice_public_url = @url
    assert @valid_takedown.valid?

    @valid_takedown.notice_public_url = bad_url

    refute @valid_takedown.valid?
    refute_nil @valid_takedown.errors[:notice_public_url]
  end

  test "can be initiated from a BulkDmcaTakedown::Notice object" do
    @url = "https://github.com/github/dmca/blob/master/2011/2011-01-27-sony.markdown"
    @text =
      <<~HEREDOC
          #{@repos[0].http_url.chomp('.git')}/blob/xxx/README.md
          #{@repos[1].http_url.chomp('.git')}/blob/xxx/SECRET.md
          #{@repos[2].http_url.chomp('.git')}/blob/xxx/README.md
        HEREDOC

    notice = Stafftools::BulkDmcaTakedown::Notice.new({ notice_text: @text, public_url: @url })

    batch = Stafftools::BulkDmcaTakedown.from_notice(notice, @staff)
    assert_equal batch.notice_public_url, notice.public_url
    assert_equal batch.repositories, notice.repositories
  end

  test "job status no work done" do
    @valid_takedown.execute
    status = {
      @valid_takedown.repositories[0].id => { user_display_status: "pending" },
      @valid_takedown.repositories[1].id => { user_display_status: "pending" },
      @valid_takedown.repositories[2].id => { user_display_status: "pending" },
    }
    assert_equal @valid_takedown.takedown_status, status
  end

  test "job status partially done, even when multiple queued, skips checking the job status" do

    takedown = Stafftools::BulkDmcaTakedown.create({ repositories: @repos[1..2], disabling_user: @staff, notice_public_url: @url })
    perform_enqueued_jobs(only: [DisableRepositoryAccessJob]) do
      takedown.execute
    end
    @valid_takedown.execute
    status = {
      @valid_takedown.repositories[0].id => { user_display_status: "pending" },
      @valid_takedown.repositories[1].id => { user_display_status: "disabled" },
      @valid_takedown.repositories[2].id => { user_display_status: "disabled" },
    }

    assert_equal status, @valid_takedown.reload.takedown_status

    perform_enqueued_jobs(only: [DisableRepositoryAccessJob])
    status = {
      @valid_takedown.repositories[0].id => { user_display_status: "disabled" },
      @valid_takedown.repositories[1].id => { user_display_status: "disabled" },
      @valid_takedown.repositories[2].id => { user_display_status: "disabled" },
    }

    assert_equal status, @valid_takedown.reload.takedown_status
  end

  test "all repo's disabled" do
    perform_enqueued_jobs(only: [DisableRepositoryAccessJob]) do
      @valid_takedown.execute
    end
    status = {
      @valid_takedown.repositories[0].id => { user_display_status: "disabled" },
      @valid_takedown.repositories[1].id => { user_display_status: "disabled" },
      @valid_takedown.repositories[2].id => { user_display_status: "disabled" },
    }

    assert_equal status, @valid_takedown.reload.takedown_status
  end

  test "Jobs update overall status on bulk object from create to queue" do

    takedown = Stafftools::BulkDmcaTakedown.create({ repositories: @repos, disabling_user: @staff, notice_public_url: @url })
    assert_equal "not_started", takedown.status

    assert_enqueued_jobs 3, only: DisableRepositoryAccessJob do
      takedown.execute
    end

    assert_equal "queued", takedown.reload.status
  end

  test "Jobs update overall status on bulk object from running to completion" do
    takedown = Stafftools::BulkDmcaTakedown.create({ repositories: @repos, disabling_user: @staff, notice_public_url: @url })
    perform_enqueued_jobs(only: [DisableRepositoryAccessJob]) do
      takedown.execute
      assert_equal "success", takedown.reload.status
    end
  end

  test "set running" do
    takedown = Stafftools::BulkDmcaTakedown.create({ repositories: @repos, disabling_user: @staff, notice_public_url: @url })

    assert_equal "not_started", takedown.status
    takedown.execute

    Stafftools::BulkDmcaTakedown.set_running_state(@repos[0])

    assert_equal "running", takedown.reload.status
  end

  test "set done only trigggers success when all jobs are done" do
    takedown = Stafftools::BulkDmcaTakedown.create({ repositories: @repos, disabling_user: @staff, notice_public_url: @url })

    assert_equal "not_started", takedown.status
    takedown.execute

    Stafftools::BulkDmcaTakedown.set_running_state(@repos[0])

    Stafftools::BulkDmcaTakedown.notify_job_done(@repos[0])

    assert_equal "running", takedown.reload.status
    perform_enqueued_jobs(only: [DisableRepositoryAccessJob])

    assert_equal "success", takedown.reload.status
  end

  test "if one of the repos was not taken down and the jobs are done we move to error state" do
    perform_enqueued_jobs(only: [DisableRepositoryAccessJob]) do
      @valid_takedown.execute
    end
    # Pretend that a repo failed to get taken down
    @repos[0].reload.access.enable(@staff)
    @valid_takedown.update(status: :running)
    Stafftools::BulkDmcaTakedown.notify_job_done(@repos[0])
    assert_equal "error", @valid_takedown.reload.status
  end


  context "TakedownStatus" do
    test "job still running" do
      status = create_fake_takedown_status("success", false)
      refute status.job_still_running?
      status2 = create_fake_takedown_status("error", false)
      refute status2.job_still_running?
      status3 = create_fake_takedown_status(nil, true)
      refute status3.job_still_running?
      status4 = create_fake_takedown_status("success", true)
      refute status4.job_still_running?
      status5 = create_fake_takedown_status("queued", false)
      assert status5.job_still_running?
      status6 = create_fake_takedown_status("running", false)
      assert status5.job_still_running?
    end

    test "error suspected" do
      status = create_fake_takedown_status("success", false)
      assert status.error_suspected?
      status2 = create_fake_takedown_status("error", false)
      assert status2.error_suspected?
      status3 = create_fake_takedown_status("error", true)
      assert status3.error_suspected?
      status4 = create_fake_takedown_status("success", true)
      refute status4.error_suspected?
      status5 = create_fake_takedown_status(nil, true)
      refute status5.error_suspected?
      status6 = create_fake_takedown_status("started", false)
      refute status6.error_suspected?
      status7 = create_fake_takedown_status(nil, true)
      refute status7.error_suspected?
      status8 = create_fake_takedown_status("queued", false)
      refute status8.error_suspected?
    end
  end

  class AccessStruct < T::Struct
    prop :disabled, T::Boolean

    def disabled?
      disabled
    end
  end

  def create_fake_takedown_status(status, disabled)
    repo1 = RepoMock.new
    repo1.disable_access_job_status = status

    repo1.access = AccessStruct.new(disabled:)
    Stafftools::DisableRepositoryAccessStatus.new(repo1)
  end
end unless GitHub.enterprise?
