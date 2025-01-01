
# typed: true
# frozen_string_literal: true

require "test_helper"

class Integration
  class UninstallServiceTest < GitHub::TestCase
    setup do
      @integration = create(:integration)
      @user = @integration.owner
    end

    context "uninstall_all" do
      test "should return success result when bulk uninstall is enqueued" do
        Integration.stubs(:locked_for_bulk_uninstalls?).returns(false)
        Integration.stubs(:lock_for_bulk_uninstalls).returns(true)
        BulkUninstallIntegrationInstallationsJob.expects(:perform_later).with(@user.id, @integration.id, staff_actor: false)

        result = Integration::UninstallService.uninstall_all(integration: @integration, current_user: @user)

        assert result.success?
        assert_equal "A job has been enqueued to uninstall all installations of #{@integration.slug}.", result.message
      end

      test "should return failure result when bulk uninstall is already in progress" do
        Integration.stubs(:locked_for_bulk_uninstalls?).returns(true)

        result = Integration::UninstallService.uninstall_all(integration: @integration, current_user: @user)

        assert_not result.success?
        assert_equal "A bulk uninstall is already in progress for this integration.", result.message
      end

      test "should return failure result when failed to enqueue uninstall job" do
        Integration.stubs(:locked_for_bulk_uninstalls?).returns(false)
        Integration.stubs(:lock_for_bulk_uninstalls).returns(false)

        result = Integration::UninstallService.uninstall_all(integration: @integration, current_user: @user)

        assert_not result.success?
        assert_equal "Failed to enqueue an uninstall job.", result.message
      end

      test "should pass staff_actor flag to job" do
        Integration.stubs(:locked_for_bulk_uninstalls?).returns(false)
        Integration.stubs(:lock_for_bulk_uninstalls).returns(true)
        BulkUninstallIntegrationInstallationsJob.expects(:perform_later).with(@user.id, @integration.id, staff_actor: true)

        result = Integration::UninstallService.uninstall_all(integration: @integration, current_user: @user, staff_actor: true)

        assert result.success?
        assert_equal "A job has been enqueued to uninstall all installations of #{@integration.slug}.", result.message
      end
    end

    context "cancel_uninstall_all" do
      test "should return success result when bulk uninstall is cancelled" do
        Integration.expects(:release_bulk_uninstalls_lock).with(@integration).returns(true)

        result = Integration::UninstallService.cancel_uninstall_all(integration: @integration)

        assert result.success?
        assert_equal "Successfully cancelled uninstalling all installations.", result.message
      end

      test "should return failure result when cancellation fails" do
        Integration.expects(:release_bulk_uninstalls_lock).with(@integration).raises(StandardError.new("Lock release failed"))
        Failbot.expects(:report)

        result = Integration::UninstallService.cancel_uninstall_all(integration: @integration)

        assert_not result.success?
        assert_equal "Failed to cancel uninstalling all installations.", result.message
      end
    end
  end
end
