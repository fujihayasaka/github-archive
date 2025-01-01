# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class RemoveIntegrationTokensJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @org = create(:organization)
    @integration = create(:integration, owner: @org)
  end

  test "destroys grants for the given integration" do
    2.times do
      user = create(:user)
      grant = @integration.grant(user, entry_point: :test_case)
      assert_predicate grant, :valid?
    end

    assert_equal 2, @integration.authorizations.count
    Timecop.freeze(1.second.from_now) do
      RemoveIntegrationTokensJob.perform_now(@integration, entry_point: :test_case)
    end
    assert_equal 0, @integration.authorizations.count
  end

  test "instruments when tokens are revoked" do
    user = create(:user)
    grant = @integration.grant(user, entry_point: :test_case)
    assert_predicate grant, :valid?

    events = subscribe "integration.revoke_tokens"
    Timecop.freeze(1.second.from_now) do
      RemoveIntegrationTokensJob.perform_now(@integration, entry_point: :test_case)
    end

    expected_payload = {
      name: @integration.name,
      slug: @integration.slug,
      tokens_revoked: 1,
      integration: @integration.name,
      integration_id: @integration.id,
      app: @integration.name,
      app_id: @integration.id,
      org: @org.login,
      org_id: @org.id,
    }

    assert event = events.pop, "not instrumented"
    assert_equal "integration.revoke_tokens", event.name
    assert_equal expected_payload, event.payload
  end

  test "re-enqueues when duration is exceeded" do
    3.times do
      user = create(:user)
      grant = @integration.grant(user, entry_point: :test_case)
      assert_predicate grant, :valid?
    end

    assert_equal 3, @integration.authorizations.count
    Timecop.travel(1.minute) do
      # The job finds in batches, meaning 3 jobs will revoke a single
      # authorization each and the 4th will find none and exit early.
      assert_performed_jobs(4, only: RemoveIntegrationTokensJob) do
        RemoveIntegrationTokensJob.perform_later(@integration, duration: 0, entry_point: :test_case)
      end
    end
    assert_equal 0, @integration.authorizations.count
  end

  test "only deletes authorizations created before created_before param" do
    3.times do
      user = create(:user)
      grant = @integration.grant(user, entry_point: :test_case)
      assert_predicate grant, :valid?
    end

    assert_equal 3, @integration.authorizations.count
    Timecop.freeze do
      assert_performed_with(job: RemoveIntegrationTokensJob, args: [@integration, duration: 0, created_before: Date.yesterday.to_time.iso8601, entry_point: :test_case]) do
        RemoveIntegrationTokensJob.perform_later(@integration, duration: 0, created_before: Date.yesterday.to_time.iso8601, entry_point: :test_case)
      end
    end
    assert_equal 3, @integration.authorizations.count
  end

  test "re-enqueues with created_before param" do
    3.times do
      user = create(:user)
      grant = @integration.grant(user, entry_point: :test_case)
      assert_predicate grant, :valid?
    end

    assert_equal 3, @integration.authorizations.count
    Timecop.freeze do
      assert_performed_with(job: RemoveIntegrationTokensJob, args: [@integration, duration: 0, created_before: Date.tomorrow.to_time.iso8601, entry_point: :test_case]) do
        RemoveIntegrationTokensJob.perform_later(@integration, duration: 0, created_before: Date.tomorrow.to_time.iso8601, entry_point: :test_case)
      end
    end
    assert_equal 0, @integration.authorizations.count
  end

  test "re-enqueues with defaulted created_before param" do
    3.times do
      user = create(:user)
      grant = @integration.grant(user, entry_point: :test_case)
      assert_predicate grant, :valid?
    end

    assert_equal 3, @integration.authorizations.count
    Timecop.freeze(1.minute.from_now) do
      assert_performed_with(job: RemoveIntegrationTokensJob, args: [@integration, duration: 0, created_before: Time.now.iso8601, entry_point: :test_case]) do
        RemoveIntegrationTokensJob.perform_later(@integration, duration: 0, entry_point: :test_case)
      end
    end
    assert_equal 0, @integration.authorizations.count
  end

  test "retry conditions" do
    assert_retry_on_dirty_exit job: RemoveIntegrationTokensJob, args: [@integration]
  end
end
