# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class ScopedIntegrationInstallableExpirationExtensionJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    user = create(:user)
    repo = create(:repository, :minimal, owner: user)

    installation = make_integration_installation(target: user, permissions: { "metadata" => :read })
    integration = installation.integration

    result = ScopedIntegrationInstallation::Creator.perform(
      installation, repositories: [repo], entry_point: :test_case
    )
    assert_predicate result, :success?

    @subject = result.installation
  end

  setup do
    reset_job_hash_locks
  end

  test "extends the expiration of the installation and associated permissions" do
    previous_expires_at = @subject.expires_at
    # Use Time.at to trim the timestamp to the nearest second. This is necessary
    # because expires_at is a timestamp with precision to the second.
    expected_expires_at = timestamp = Time.at(2.days.from_now.to_i)
    ScopedIntegrationInstallableExpirationExtensionJob.perform_now(
      @subject, timestamp, entry_point: :test_case,
    )
    refute_equal previous_expires_at, @subject.reload.expires_at
    assert_equal expected_expires_at, @subject.expires_at
  end

  test "retry conditions" do
    timestamp = Time.now
    assert_retry_on_dirty_exit job: ScopedIntegrationInstallableExpirationExtensionJob,
                               args: [@subject, timestamp]
  end

  test "locks by installable" do
    assert_enqueued_jobs 1, only: ScopedIntegrationInstallableExpirationExtensionJob do
      job = ScopedIntegrationInstallableExpirationExtensionJob.perform_later(
        @subject, 2.days.from_now.to_i, entry_point: :test_case,
      )

      assert_predicate job, :locked?
      assert_equal "ScopedIntegrationInstallation:#{@subject.id}", T.unsafe(job).lock_key

      ScopedIntegrationInstallableExpirationExtensionJob.perform_later(
        @subject, 3.days.from_now.to_i, entry_point: :test_case,
      )
    end
  end
end
