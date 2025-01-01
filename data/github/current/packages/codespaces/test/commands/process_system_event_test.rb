# typed: true
# frozen_string_literal: true

require "test_helper"

module Codespaces
  class ProcessSystemEventTest < GitHub::TestCase
    fixtures do
      @codespace = create(:codespace)
    end

    test "it calls TransferBillableOwner with codespace", skip_enterprise: true do
      Codespaces::TransferBillableOwner.expects(:call).with(@codespace)
      Codespaces::ProcessSystemEvent.call([@codespace])
    end

    test "it skips the clean up job if the codespace is still accessible", skip_enterprise: true do
      Codespaces::TransferBillableOwner.expects(:call).with(@codespace)
      CodespacesSuspendEnvironmentJob.expects(:perform_later).never
      Codespaces::CleanUpInaccessibleJob.expects(:perform_after_waiting_period).never
      Codespaces::ProcessSystemEvent.call([@codespace])
    end

    test "it stops the codespace and calls the clean up job if the codespace is inaccessible", skip_enterprise: true do
      org = create(:codespaces_organization, plan: GitHub::Plan.business)
      private_repo = create(:private_repository, owner: org)
      user = create(:user)
      org.add_member(user)

      codespace = create(:codespace, owner: user, repository: private_repo)

      org.update_organization_codespaces_user_limit(Configurable::OrganizationCodespacesUserLimit::DISABLED, actor: org.admins.first)
      Codespaces::TransferBillableOwner.expects(:call).with(codespace)
      waiting_period = Codespaces::ProcessSystemEvent::CLEAN_UP_INACCESSIBLE_CODESPACE_WAITING_PERIOD
      CodespacesSuspendEnvironmentJob.expects(:perform_later).with(codespace: codespace, ignore_deleted: true)
      Codespaces::CleanUpInaccessibleJob.expects(:perform_after_waiting_period).with(waiting_period: waiting_period, codespace: codespace, reason: Codespace.deletion_reasons[:process_system_event])
      Codespaces::ProcessSystemEvent.call([codespace])
    end

    test "errors are caught and reported with a codespace id attached to them", skip_enterprise: true do
      err = StandardError.new("some error")
      Codespaces::TransferBillableOwner.expects(:call).with(@codespace).raises(err)
      Codespaces::ErrorReporter.expects(:push).with(codespace_id: @codespace.id)
      Codespaces::ErrorReporter.expects(:report).with(err)
      Codespaces::ProcessSystemEvent.call([@codespace])
    end

    test "specifies the appropriate deletion reason", skip_enterprise: true do
      org = create(:codespaces_organization, plan: GitHub::Plan.business)
      private_repo = create(:private_repository, owner: org)
      user = create(:user)
      org.add_member(user)

      codespace = create(:codespace, owner: user, repository: private_repo)

      org.update_organization_codespaces_user_limit(Configurable::OrganizationCodespacesUserLimit::DISABLED, actor: org.admins.first)
      Codespaces::TransferBillableOwner.expects(:call).with(codespace)
      waiting_period = Codespaces::ProcessSystemEvent::CLEAN_UP_INACCESSIBLE_CODESPACE_WAITING_PERIOD
      CodespacesSuspendEnvironmentJob.expects(:perform_later).with(codespace: codespace, ignore_deleted: true)
      Codespaces::CleanUpInaccessibleJob.expects(:perform_after_waiting_period).with(waiting_period: waiting_period, codespace: codespace, reason: Codespace.deletion_reasons[:process_system_event])
      Codespaces::ProcessSystemEvent.call([codespace])
    end
  end
end
