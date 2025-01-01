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
    GitHub.flipper[:run_cleanup_expired_permissions_job].enable
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
    parent = make_integration_installation(target: @target, permissions: { "metadata" => :read, "contents" => :write })

    Timecop.freeze do
      result = ScopedIntegrationInstallation::Creator.perform(parent, repositories: ScopedIntegrationInstallation::Creator::INSTALL_ON_ALL_REPOSITORIES, permissions: { "metadata" => :read }, expires: true)
      assert_predicate result, :success?

      actor = result.installation

      permissions_query = Permission.where(actor_id: actor.ability_id, actor_type: actor.ability_type)
      assert permissions_query.where.not(expires_at: nil).exists?

      assert_no_difference -> { permissions_query.count }, -1 do
        CleanupExpiredPermissionsJob.perform_now
      end
    end
  end

  test "does not cleanup expired permissions when the feature flag is disabled" do
    GitHub.flipper[:run_cleanup_expired_permissions_job].disable

    parent = make_integration_installation(target: @target, permissions: { "metadata" => :read, "contents" => :write })

    Timecop.freeze do
      result = ScopedIntegrationInstallation::Creator.perform(parent, repositories: ScopedIntegrationInstallation::Creator::INSTALL_ON_ALL_REPOSITORIES, permissions: { "metadata" => :read }, expires: true)
      assert_predicate result, :success?

      actor = result.installation

      permissions_query = Permission.where(actor_id: actor.ability_id, actor_type: actor.ability_type)
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
    parent = make_integration_installation(target: @target, permissions: { "metadata" => :read, "contents" => :write })

    Timecop.freeze do
      result = ScopedIntegrationInstallation::Creator.perform(parent, repositories: ScopedIntegrationInstallation::Creator::INSTALL_ON_ALL_REPOSITORIES, permissions: { "metadata" => :read }, expires: true)
      assert_predicate result, :success?

      actor = result.installation

      permissions_query = Permission.where(actor_id: actor.ability_id, actor_type: actor.ability_type)
      assert permissions_query.where.not(expires_at: nil).exists?

      # Ensure the permissions are expired.
      Timecop.travel(1.month.from_now) do
        assert_difference -> { permissions_query.count }, -1 do
          CleanupExpiredPermissionsJob.perform_now
        end
      end
    end
  end
end
