# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class UninstallIntegrationInstallationJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @target = create(:user)
    @installation = make_integration_installation(target: @target)
  end

  test "uninstalls the app from the target" do
    perform_enqueued_jobs(only: [UninstallIntegrationInstallationJob]) do
      UninstallIntegrationInstallationJob.perform_later(@target.id, @installation.id)
    end

    refute_predicate IntegrationInstallation.where(id: @installation.id), :exists?
  end

  test "does not raise an ActiveRecord::RecordNotFound exception if the installation is missing" do
    @installation.destroy

    assert_nothing_raised do
      perform_enqueued_jobs(only: [UninstallIntegrationInstallationJob]) do
        UninstallIntegrationInstallationJob.perform_later(@target.id, @installation.id)
      end
    end
  end

  test "retry conditions" do
    assert_retry_on_dirty_exit job: UninstallIntegrationInstallationJob, args: [@target.id, @installation.id]
  end

  test "returns early if installation target is locked for deletion" do
    IntegrationInstallation.lock_target_for_deletion(@installation)

    assert_nothing_raised do
      perform_enqueued_jobs(only: [UninstallIntegrationInstallationJob]) do
        UninstallIntegrationInstallationJob.perform_later(@target.id, @installation.id)
      end
    end

    assert_predicate IntegrationInstallation.where(id: @installation.id), :exists?
  end

  test "uninstall with a staff actor", skip_enterprise: true do
    events = subscribe "integration_installation.destroy"
    staff_admin_user = create(:staff_admin_user)
    User.stubs(:staff_user).returns(staff_admin_user)

    expected_payload = {}.tap do |payload|
      payload[:installation_id]      = @installation.id
      payload[:integration]          = @installation.integration.name
      payload[:app]                  = @installation.integration.name
      payload[:integration_id]       = @installation.integration.id
      payload[:app_id]               = @installation.integration.id
      payload[:name]                 = @installation.integration.name
      payload[:slug]                 = @installation.integration.slug
      payload[:user]                 = @target.display_login
      payload[:user_id]              = @target.id
      payload[:repository_selection] = "selected"
      payload[:staff_actor]          = @target.display_login
      payload[:staff_actor_id]       = @target.id
      payload[:actor_id]             = User.staff_user.id
      payload[:actor]                = User.staff_user.display_login
    end

    perform_enqueued_jobs(only: [UninstallIntegrationInstallationJob]) do
      UninstallIntegrationInstallationJob.perform_later(@target.id, @installation.id, staff_actor: true)
    end

    assert event = events.pop, "expected an instrument deletion event"

    assert_equal "integration_installation.destroy", event.name
    assert_same_hash expected_payload, event.payload
  end

end
