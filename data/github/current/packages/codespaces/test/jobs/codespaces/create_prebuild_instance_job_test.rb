# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class CodespaceCreatePrebuildInstanceJobTest < GitHub::TestCase
  include DogstatsTestHelpers
  include CodespacesPlanFixtures

  fixtures do
    @user = create(:user)
    @org = create(:codespaces_organization, admin: @user)
    @repo = create(:repository, owner: @org)
    @pool = "testpool123"
  end

  setup do
    Codespaces::Secret.stubs(:for_prebuild).returns([[], []])
  end

  test "increments datadog if the job is forced to exit" do
    Codespaces::CreatePrebuildInstance.expects(:call).raises(Aqueduct::Worker::JobKilled.new)

    perform_enqueued_jobs(only: [Codespaces::CreatePrebuildInstanceJob]) do
      assert_raises Aqueduct::Worker::JobKilled do
        Codespaces::CreatePrebuildInstanceJob.perform_later(
          repository: @repo,
          pool_code: @pool,
          location: "EastUs",
          vscs_target: "local"
        )
      end
    end

    assert_dogstats_increment "codespaces.create_prebuild_instance_job.dirty_exit", tags: ["location:EastUs"]
  end

  test "retries if there is an error with the VSCS API" do
    Codespaces::CreatePrebuildInstance.expects(:call).at_least_once.raises(Codespaces::Client::BadResponseError.new("BOOM!"))

    Codespaces::CreatePrebuildInstanceJob.any_instance.expects(:retry_job)

    assert_nothing_raised do
      Codespaces::CreatePrebuildInstanceJob.perform_now(
        repository: @repo,
        pool_code: @pool,
        location: "EastUs"
      )
    end
  end

  test "retries if we hit a timeout" do
    Codespaces::CreatePrebuildInstance.expects(:call).raises(Codespaces::Client::TimeoutError.new("BOOM"))

    Codespaces::CreatePrebuildInstanceJob.any_instance.expects(:retry_job)

    assert_nothing_raised do
      Codespaces::CreatePrebuildInstanceJob.perform_now(
        repository: @repo,
        pool_code: @pool,
        location: "EastUs"
      )
    end
  end

  test "marks the codespaces as failed if error is not retryable" do
    Codespaces::CreatePrebuildInstance.expects(:call).raises(Codespaces::Client::ConnectionFailed.new("OH NO"))

    assert_raises StandardError do
      Codespaces::CreatePrebuildInstanceJob.perform_now(
        repository: @repo,
        pool_code: @pool,
        location: "EastUs"
      )
    end
  end

  test "increments datadog with the correct tags" do
    Codespaces::CreatePrebuildInstance.expects(:call)

    location = "EastUs"
    vscs_target = "local"
    Codespaces::CreatePrebuildInstanceJob.perform_now(
      location: location,
      repository: @repo,
      pool_code: @pool,
      vscs_target: vscs_target
    )

    tags = [
      "class:codespaces/create_prebuild_instance_job",
      "location:#{location}",
      "vscs_target:#{vscs_target}"
    ]
    assert_dogstats_increment "active_job.performed", tags: tags
  end
end unless GitHub.enterprise?
