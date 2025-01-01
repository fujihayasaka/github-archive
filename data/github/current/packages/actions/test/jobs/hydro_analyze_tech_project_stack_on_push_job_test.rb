# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroAnalyzeTechProjectStackOnPushJobTest < GitHub::TestCase
  include PushTestHelper

  fixtures do
    @repo = create(:repository, from_example: :simple)
    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  test "push to default branch enqueues RepositoryUpdateTechProjectAndStackJob" do
    assert_enqueued_jobs 1, only: RepositoryUpdateTechProjectAndStackJob do
      perform_push_hydro_job(repository: @repo, job_class: HydroAnalyzeTechProjectStackOnPushJob)
    end
  end

  test "push to non-default branch does not enqueue RepositoryUpdateTechProjectAndStackJob" do
    assert_enqueued_jobs 0, only: RepositoryUpdateTechProjectAndStackJob do
      perform_push_hydro_job(repository: @repo, branch_name: "foobar", create_branch: true, job_class: HydroAnalyzeTechProjectStackOnPushJob)
    end
  end
end
