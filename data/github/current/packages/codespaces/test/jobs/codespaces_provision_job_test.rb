# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class CodespacesProvisionJobTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @codespace = create(:codespace, :unprovisioned)
    example_repo :simple, @codespace.repository

    make_trusted_oauth_apps_owner
    @integration = create(:codespaces_integration)
  end

  test "has a lock key" do
    job1 = CodespacesProvisionJob.new(codespace: @codespace)
    job2 = CodespacesProvisionJob.new(codespace: @codespace)
    job3 = CodespacesProvisionJob.new(codespace: build(:codespace))

    assert_equal job1.lock_key, job2.lock_key
    refute_equal job1.lock_key, job3.lock_key
  end

  test "retries if the codespace is not found" do
    @codespace.delete

    CodespacesProvisionJob.any_instance.expects(:retry_job)

    assert_nothing_raised do
      perform_enqueued_jobs(only: [CodespacesProvisionJob]) do
        CodespacesProvisionJob.perform_later(codespace: @codespace)
      end
    end
  end

  test "marks the codespace as failed and increments datadog if the job is forced to exit" do
    assert_predicate @codespace, :pending?

    Codespaces::ProvisionEnvironment.expects(:call).raises(Aqueduct::Worker::JobKilled.new)


    perform_enqueued_jobs(only: [CodespacesProvisionJob]) do
      assert_raises Aqueduct::Worker::JobKilled do
        CodespacesProvisionJob.perform_later(codespace: @codespace)
      end
    end

    assert_predicate @codespace.reload, :failed?
    assert_dogstats_increment 1, "codespaces_provision_job.dirty_exit"
  end

  test "marks the codespaces as failed if retry attempts are exhausted" do
    refute_predicate @codespace, :failed?

    Codespaces::ProvisionEnvironment.expects(:call).at_least_once.raises(Codespaces::Client::BadResponseError.new("BOOM!"))


    perform_enqueued_jobs(only: [CodespacesProvisionJob]) do
      assert_raises Codespaces::Error do
        CodespacesProvisionJob.perform_later(codespace: @codespace)
      end
    end

    assert_predicate @codespace.reload, :failed?
  end

  test "retries if there is an error with the VSO API" do
    Codespaces::ProvisionEnvironment.expects(:call).raises(Codespaces::Client::BadResponseError.new("BOOM"))
    CodespacesProvisionJob.any_instance.expects(:retry_job)

    assert_nothing_raised do
      CodespacesProvisionJob.perform_now(codespace: @codespace)
    end

    assert_predicate @codespace.reload, :pending?
  end

  test "retries if we hit a timeout" do
    Codespaces::ProvisionEnvironment.expects(:call).raises(Codespaces::Client::TimeoutError.new("BOOM"))

    CodespacesProvisionJob.any_instance.expects(:retry_job)

    assert_nothing_raised do
      CodespacesProvisionJob.perform_now(codespace: @codespace)
    end

    assert_predicate @codespace.reload, :pending?
  end

  test "retries if we hit EnvironmentNotFound" do
    Codespaces::ProvisionEnvironment.expects(:call).raises(Codespaces::FindEnvironment::NotFoundError.new("OH NO"))

    CodespacesProvisionJob.any_instance.expects(:retry_job)

    assert_nothing_raised do
      CodespacesProvisionJob.perform_now(codespace: @codespace)
    end

    assert_predicate @codespace.reload, :pending?
  end

  test "retries if the backing repository is empty" do
    @codespace.repository.expects(:empty?).returns(true)
    CodespacesProvisionJob.any_instance.expects(:retry_job)

    assert_nothing_raised do
      CodespacesProvisionJob.perform_now(codespace: @codespace)
    end

    assert_predicate @codespace.reload, :pending?
  end

  test "doesn't raise if we hit repository_not_found from token minting" do
    Codespaces::Tokens.expects(:mint_github_token).raises(Codespaces::Tokens::Error.new("Could not create repository scoped grant (repository_not_found): The repository requested could not be found."))
    assert_nothing_raised do
      CodespacesProvisionJob.perform_now(codespace: @codespace)
    end

    assert_predicate @codespace.reload, :failed?
  end

  test "marks the codespaces as failed if error is not retryable" do
    Codespaces::ProvisionEnvironment.expects(:call).raises(Codespaces::Client::ConnectionFailed.new("OH NO"))

    assert_raises StandardError do
      CodespacesProvisionJob.perform_now(codespace: @codespace)
    end

    assert_predicate @codespace.reload, :failed?
  end

  test "defers to Codespaces::ProvisionEnvironment" do
    test_token_string = "some token string"

    Codespaces::Tokens.expects(:mint_github_token).with(@codespace.owner, @codespace, entry_point: nil).returns(test_token_string)
    Codespaces::ProvisionEnvironment.expects(:call).with(@codespace, environment_options: {}, github_token: test_token_string)
    CodespacesProvisionJob.perform_now(codespace: @codespace)
  end

  test "uses user_session to mint token used for provisioning" do
    test_token_string = "some token string"

    Codespaces::Tokens.expects(:mint_github_token).with(@codespace.owner, @codespace, entry_point: nil).returns(test_token_string)

    Codespaces::ProvisionEnvironment.expects(:call).with(@codespace, environment_options: {}, github_token: test_token_string)
    CodespacesProvisionJob.perform_now(codespace: @codespace)
  end

  test "retries if token minting exceptions are encountered" do
    Codespaces::Tokens.expects(:mint_github_token).with(@codespace.owner, @codespace, entry_point: nil).raises(Codespaces::Tokens::Error.new)

    CodespacesProvisionJob.any_instance.expects(:retry_job)

    assert_nothing_raised do
      perform_enqueued_jobs(only: [CodespacesProvisionJob]) do
        CodespacesProvisionJob.perform_now(codespace: @codespace)
      end
    end
  end

  test "bails before trying to fail the codespace if it's already provisioned" do
    Codespaces::Tokens.expects(:mint_github_token).never

    provisioned = create(:codespace)
    example_repo :simple, provisioned.repository

    CodespacesProvisionJob.perform_now(codespace: provisioned)

    assert provisioned.reload.provisioned?
  end

  test "bails early if the codespace was marked as failed" do
    Codespaces::Tokens.expects(:mint_github_token).never

    failed = create(:codespace, :failed)
    example_repo :simple, failed.repository

    CodespacesProvisionJob.perform_now(codespace: failed)
  end

  test "bails early if the codespace was deleted before it ran" do
    Codespaces::Tokens.expects(:mint_github_token).never

    failed = create(:codespace, :deleted)
    example_repo :simple, failed.repository

    CodespacesProvisionJob.perform_now(codespace: failed)
  end
end unless GitHub.enterprise?
