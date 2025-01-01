# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProject
  class ResyncItemsTest < GitHub::TestCase
    include GitHub::LoggerHelper

    fixtures do
      @user = create(:verified_user)
      @org = create(:organization, admin: @user)
    end

    context ".resync_later" do
      test "queue multiple jobs to resync the project's items" do
        first_memex_project = create(:memex_project, owner: @org)
        second_memex_project = create(:memex_project, owner: @org)

        assert_enqueued_jobs 2, only: ResyncMemexProjectItemsIndexJob do
          MemexProject::ResyncItems.resync_later([
            first_memex_project.id,
            second_memex_project.id,
          ])
        end
      end

      test "returns projects that failed to enqueue their resync jobs" do
        first_memex_project = create(:memex_project, owner: @org)
        second_memex_project = create(:memex_project, owner: @org)
        first_job_status = ResyncMemexProjectItemsIndexJobStatus.create(first_memex_project.id)
        second_job_status = ResyncMemexProjectItemsIndexJobStatus.create(second_memex_project.id)
        first_job_status.error!
        ResyncMemexProjectItemsIndexJobStatus.stubs(:create).returns(first_job_status).then.returns(second_job_status)

        assert_enqueued_jobs 1, only: ResyncMemexProjectItemsIndexJob do
          failed_project_ids = MemexProject::ResyncItems.resync_later([
            first_memex_project.id,
            second_memex_project.id,
          ])

          assert_equal [first_memex_project.id], failed_project_ids
        end
      end

      test "logs when project id for resyncing when none provided" do
        first_memex_project = create(:memex_project, owner: @org)
        second_memex_project = create(:memex_project, owner: @org)
        first_job_status = ResyncMemexProjectItemsIndexJobStatus.create(first_memex_project.id)
        second_job_status = ResyncMemexProjectItemsIndexJobStatus.create(second_memex_project.id)
        first_job_status.error!
        ResyncMemexProjectItemsIndexJobStatus.stubs(:create).returns(first_job_status).then.returns(second_job_status)

        assert_logged(
          "Body" => "Could not enqueue resync job for project",
          "code.namespace" => "MemexProject::ResyncItems",
          "code.function" => "resync_later",
          "gh.memex.project.id" => first_memex_project.id,
        ) do
          failed_project_ids = MemexProject::ResyncItems.resync_later([
            first_memex_project.id,
            second_memex_project.id,
          ])

          assert_equal [first_memex_project.id], failed_project_ids
        end
      end

      test "enable_beta_flag kwarg" do
        memex_project = create(:memex_project, owner: @org)
        job_status = ResyncMemexProjectItemsIndexJobStatus.create(memex_project.id)
        ResyncMemexProjectItemsIndexJobStatus.stubs(:create).returns(job_status)

        enqueued_job = assert_enqueued_with(job: ResyncMemexProjectItemsIndexJob) do
          MemexProject::ResyncItems.resync_later([memex_project.id])
        end

        _project_id, _job_status_id, kwargs = enqueued_job.arguments
        assert_nil kwargs[:enable_beta_flag], "Expected enable_beta_flag to be nil by default"
      end

      test "forwards enable_beta_flag kwarg" do
        memex_project = create(:memex_project, owner: @org)
        job_status = ResyncMemexProjectItemsIndexJobStatus.create(memex_project.id)
        ResyncMemexProjectItemsIndexJobStatus.stubs(:create).returns(job_status)

        enqueued_job = assert_enqueued_with(job: ResyncMemexProjectItemsIndexJob) do
          MemexProject::ResyncItems.resync_later([memex_project.id], enable_beta_flag: true)
        end

        _project_id, _job_status_id, kwargs = enqueued_job.arguments
        assert_equal true, kwargs[:enable_beta_flag]
      end

      test "read_only kwarg" do
        memex_project = create(:memex_project, owner: @org)
        job_status = ResyncMemexProjectItemsIndexJobStatus.create(memex_project.id)
        ResyncMemexProjectItemsIndexJobStatus.stubs(:create).returns(job_status)

        enqueued_job = assert_enqueued_with(job: ResyncMemexProjectItemsIndexJob) do
          MemexProject::ResyncItems.resync_later([memex_project.id])
        end

        _project_id, _job_status_id, kwargs = enqueued_job.arguments
        assert_nil kwargs[:read_only], "Expected read_only to be nil by default"
      end

      test "forwards read_only kwarg" do
        memex_project = create(:memex_project, owner: @org)
        job_status = ResyncMemexProjectItemsIndexJobStatus.create(memex_project.id)
        ResyncMemexProjectItemsIndexJobStatus.stubs(:create).returns(job_status)

        enqueued_job = assert_enqueued_with(job: ResyncMemexProjectItemsIndexJob) do
          MemexProject::ResyncItems.resync_later([memex_project.id], read_only: true)
        end

        _project_id, _job_status_id, kwargs = enqueued_job.arguments
        assert_equal true, kwargs[:read_only]
      end
    end

    context "#resync_later" do
      test "enqueues a job to resync the project's items" do
        memex_project = create(:memex_project, owner: @org)
        resync_items = MemexProject::ResyncItems.new(memex_project.id)

        enqueued_job = assert_enqueued_with(job: ResyncMemexProjectItemsIndexJob) do
          resync_items.resync_later
        end

        project_id, = enqueued_job.arguments
        assert_equal memex_project.id, project_id
      end

      test "raises JobStatusError when job status is blank" do
        ResyncMemexProjectItemsIndexJobStatus.stubs(:create).returns(nil)
        memex_project = create(:memex_project, owner: @org)
        resync_items = MemexProject::ResyncItems.new(memex_project.id)

        assert_no_enqueued_jobs do
          exception = assert_raises MemexProject::ResyncItems::JobStatusError do
            resync_items.resync_later
          end

          assert_equal "No job status reported.", exception.message
        end
      end

      test "raises JobStatusError when job status returned an error" do
        memex_project = create(:memex_project, owner: @org)
        resync_items = MemexProject::ResyncItems.new(memex_project.id)
        job_status = ResyncMemexProjectItemsIndexJobStatus.create(memex_project.id)
        job_status.error!("My error message.")
        ResyncMemexProjectItemsIndexJobStatus.stubs(:create).returns(job_status)

        assert_no_enqueued_jobs do
          exception = assert_raises MemexProject::ResyncItems::JobStatusError do
            resync_items.resync_later
          end

          assert_equal "My error message.", exception.message
        end
      end

      test "enable_beta_flag kwarg is nil by default" do
        memex_project = create(:memex_project, owner: @org)
        resync_items = MemexProject::ResyncItems.new(memex_project.id)

        enqueued_job = assert_enqueued_with(job: ResyncMemexProjectItemsIndexJob) do
          resync_items.resync_later
        end

        _project_id, _job_status_id, kwargs = enqueued_job.arguments
        assert_nil kwargs[:enable_beta_flag], "Expected enable_beta_flag to be nil by default"
      end

      test "forwards enable_beta_flag kwarg to background job" do
        memex_project = create(:memex_project, owner: @org)
        job_status = ResyncMemexProjectItemsIndexJobStatus.create(memex_project.id)
        resync_items = MemexProject::ResyncItems.new(memex_project.id, enable_beta_flag: true)

        enqueued_job = assert_enqueued_with(job: ResyncMemexProjectItemsIndexJob) do
          resync_items.resync_later
        end

        _project_id, _job_status_id, kwargs = enqueued_job.arguments
        assert_equal true, kwargs[:enable_beta_flag]
      end

      test "read_only kwarg is nil by default" do
        memex_project = create(:memex_project, owner: @org)
        resync_items = MemexProject::ResyncItems.new(memex_project.id)

        enqueued_job = assert_enqueued_with(job: ResyncMemexProjectItemsIndexJob) do
          resync_items.resync_later
        end

        _project_id, _job_status_id, kwargs = enqueued_job.arguments
        assert_nil kwargs[:read_only], "Expected read_only to be nil by default"
      end

      test "forwards read_only kwarg to background job" do
        memex_project = create(:memex_project, owner: @org)
        job_status = ResyncMemexProjectItemsIndexJobStatus.create(memex_project.id)
        resync_items = MemexProject::ResyncItems.new(memex_project.id, read_only: true)

        enqueued_job = assert_enqueued_with(job: ResyncMemexProjectItemsIndexJob) do
          resync_items.resync_later
        end

        _project_id, _job_status_id, kwargs = enqueued_job.arguments
        assert_equal true, kwargs[:read_only]
      end
    end
  end
end
