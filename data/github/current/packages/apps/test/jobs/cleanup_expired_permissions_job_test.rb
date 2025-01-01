# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class CleanupExpiredPermissionsJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @target = create(:organization)
  end

  setup do
    enable_feature_flag(:run_cleanup_expired_permissions_job)
  end

  test "does not cleanup permissions that do not have an expiration" do
    Timecop.freeze do
      actor = make_integration_installation(target: @target, permissions: { "metadata" => :read })
      refute Permission.where(actor_id: actor.ability_id, actor_type: actor.ability_id).where.not(expires_at: nil).exists?

      assert_no_difference -> { Permission.where(actor_id: actor.ability_id, actor_type: actor.ability_type).count } do
        CleanupExpiredPermissionsJob.perform_now
      end
    end
  end

  test "does not cleanup permissions that have not expired" do
    installation = make_integration_installation(target: @target, permissions: { "metadata" => :read, "contents" => :write })

    Timecop.freeze do
      Permission.where(actor_id: installation.ability_id, actor_type: installation.ability_type).update_all(expires_at: 1.month.from_now)

      permissions_query = Permission.where(actor_id: installation.ability_id, actor_type: installation.ability_type)
      assert permissions_query.where.not(expires_at: nil).exists?

      assert_no_difference -> { permissions_query.count }, -1 do
        CleanupExpiredPermissionsJob.perform_now
      end
    end
  end

  test "does not cleanup expired permissions when the feature flag is disabled" do
    disable_feature_flag(:run_cleanup_expired_permissions_job)

    installation = make_integration_installation(target: @target, permissions: { "metadata" => :read, "contents" => :write })

    Timecop.freeze do
      Permission.where(actor_id: installation.ability_id, actor_type: installation.ability_type).update_all(expires_at: 10.days.from_now)

      permissions_query = Permission.where(actor_id: installation.ability_id, actor_type: installation.ability_type)
      assert permissions_query.where.not(expires_at: nil).exists?

      # Ensure the permissions are expired.
      Timecop.travel(1.month.from_now) do
        assert_no_difference -> { permissions_query.count } do
          CleanupExpiredPermissionsJob.perform_now
        end
      end
    end
  end

  test "cleans up expired permissions" do
    installation = make_integration_installation(target: @target, permissions: { "metadata" => :read, "contents" => :write })

    Timecop.freeze do
      Permission.where(actor_id: installation.ability_id, actor_type: installation.ability_type).update_all(expires_at: 10.days.from_now)

      permissions_query = Permission.where(actor_id: installation.ability_id, actor_type: installation.ability_type)
      assert permissions_query.where.not(expires_at: nil).exists?

      # Ensure the permissions are expired.
      Timecop.travel(1.month.from_now) do
        assert_difference -> { permissions_query.count }, -2 do
          CleanupExpiredPermissionsJob.perform_now
        end
      end
    end
  end
end
