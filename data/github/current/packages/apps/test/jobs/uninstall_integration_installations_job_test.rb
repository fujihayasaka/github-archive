# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class BulkUninstallIntegrationInstallationsJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper

  setup do
    @integration = create(:integration)
    @actor = create(:user)
    @installations = 3.times.map do
      make_integration_installation(target: create(:organization), integration: @integration)
    end
    self.perform_enqueued_jobs = [BulkUninstallIntegrationInstallationsJob]
    Integration.lock_for_bulk_uninstalls(@integration)
  end

  test "uninstalls all installations", skip_if_feature_disabled: :bulk_uninstalls do
    assert_difference -> { @integration.installations.count }, -3 do
      BulkUninstallIntegrationInstallationsJob.perform_now(@actor.id, @integration.id)
    end

    refute Integration.locked_for_bulk_uninstalls?(@integration)
  end

  test "doesn't uninstall any installations if lock not acquired", skip_if_feature_disabled: :bulk_uninstalls do
    Integration.release_bulk_uninstalls_lock(@integration)

    assert_difference -> { @integration.installations.count }, 0 do
      BulkUninstallIntegrationInstallationsJob.perform_now(@actor.id, @integration.id)
    end

    refute Integration.locked_for_bulk_uninstalls?(@integration)
  end

  test "preserves staff_actor flag when re-enqueueing", skip_if_feature_disabled: :bulk_uninstalls do
    GitHub::SafeTimer.any_instance.stubs(:run?).returns(false)

    BulkUninstallIntegrationInstallationsJob.expects(:perform_later).with(
      @actor.id,
      @integration.id,
      staff_actor: true
    )

    BulkUninstallIntegrationInstallationsJob.perform_now(
      @actor.id,
      @integration.id,
      staff_actor: true
    )
  end

  test "handles race condition when installation is deleted by another process", skip_if_feature_disabled: :bulk_uninstalls do
    installation_one = @installations.first
    installation_two = @installations.last

    IntegrationInstallation.any_instance.expects(:uninstall)
      .at_least_once
      .with(actor: @actor, staff_actor: false)
      .raises(ActiveRecord::RecordNotFound)

    assert_nothing_raised do
      BulkUninstallIntegrationInstallationsJob.perform_now(@actor.id, @integration.id)
    end
  end

  test "continues uninstalling if already locked", skip_if_feature_disabled: :bulk_uninstalls do
    Integration.lock_for_bulk_uninstalls(@integration)

    assert_difference -> { @integration.installations.count }, -3 do
      BulkUninstallIntegrationInstallationsJob.perform_now(@actor.id, @integration.id)
    end
  end

  test "enqueues another job if timing out", skip_if_feature_disabled: :bulk_uninstalls do
    GitHub::SafeTimer.any_instance.stubs(:run?).returns(false)

    BulkUninstallIntegrationInstallationsJob.expects(:perform_later).with(@actor.id, @integration.id, staff_actor: false)
    BulkUninstallIntegrationInstallationsJob.perform_now(@actor.id, @integration.id)
  end

  test "stops if bulk_uninstall feature is disabled" do
    disable_feature_flag(:bulk_uninstall)

    assert_no_difference -> { @integration.installations.count } do
      BulkUninstallIntegrationInstallationsJob.perform_now(@actor.id, @integration.id)
    end
  end

  test "releases lock when no installations remain", skip_if_feature_disabled: :bulk_uninstalls do
    @integration.installations.destroy_all

    BulkUninstallIntegrationInstallationsJob.perform_now(@actor.id, @integration.id)

    refute Integration.locked_for_bulk_uninstalls?(@integration)
  end

  test "throttles uninstallation requests", skip_if_feature_disabled: :bulk_uninstalls do
    IntegrationInstallation.expects(:throttle).once

    BulkUninstallIntegrationInstallationsJob.perform_now(@actor.id, @integration.id)
  end

  test "supports retries when errors occur", skip_if_feature_disabled: :bulk_uninstalls do
    assert_retry_on_dirty_exit job: BulkUninstallIntegrationInstallationsJob, args: [@actor.id, @integration.id]
  end

  test "uninstalls with staff actor when specified", skip_if_feature_disabled: :bulk_uninstalls do
    IntegrationInstallation.any_instance.expects(:uninstall).with(actor: @actor, staff_actor: true).at_least_once

    BulkUninstallIntegrationInstallationsJob.perform_now(@actor.id, @integration.id, staff_actor: true)
  end

  test "uses correct queue" do
    assert_equal "bulk_uninstall_integration_installations", BulkUninstallIntegrationInstallationsJob.queue_name
  end

  test "processes installations within time limit", skip_if_feature_disabled: :bulk_uninstalls do
    GitHub::SafeTimer.expects(:timeout).with(BulkUninstallIntegrationInstallationsJob::TIME_LIMIT)

    BulkUninstallIntegrationInstallationsJob.perform_now(@actor.id, @integration.id)
  end

  test "handles invalid integration id gracefully" do
    assert_raises ActiveRecord::RecordNotFound do
      BulkUninstallIntegrationInstallationsJob.perform_now(@actor.id, -1)
    end
  end

  test "handles invalid actor id gracefully" do
    assert_raises ActiveRecord::RecordNotFound do
      BulkUninstallIntegrationInstallationsJob.perform_now(-1, @integration.id)
    end
  end
end
