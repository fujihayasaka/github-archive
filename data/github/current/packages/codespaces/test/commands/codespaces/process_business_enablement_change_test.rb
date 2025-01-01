# typed: true
# frozen_string_literal: true

require "test_helper"

module Codespaces
  class ProcessBusinessEnablementChangeTest < GitHub::TestCase
    fixtures do
      @business = create(:business)
      @org = create(:codespaces_organization)
      @org2 = create(:codespaces_organization)
      @business.add_organization(@org)
      @business.add_organization(@org2)
      @user = @business.owners.first
    end

    context "when codespaces are disabled", skip_enterprise: true do
      test "change to enablement enqueues soft delete job to stops and all org-billed codespaces" do
        repo = create(:private_repository, owner: @org)
        other_user = create(:user)
        repo.add_member(other_user, action: :admin)
        codespace = create(:codespace, repository: repo)
        codespace.update(owner: other_user, billable_owner: other_user)

        refute_equal codespace.owner, @org
        refute_equal codespace.billable_owner, @org

        assert codespace.reload.accessible?

        Codespaces::CleanUpInaccessibleJob.expects(:perform_after_waiting_period).with(waiting_period: 7.days, codespace: codespace, reason: Codespace.deletion_reasons[:process_system_event])

        perform_enqueued_jobs(only: [
          Codespaces::OrgSettingsChangedJob,
          CodespacesProcessSystemEventJob,
          Codespaces::CleanUpInaccessibleJob,
          CodespacesSuspendEnvironmentJob]) do
          Codespaces::ProcessBusinessEnablementChange.call(
            business: @business,
            actor: @user,
            enablement: Codespaces::EnablementPolicyInputPresenter::DISABLED
          )
        end

        refute codespace.reload.accessible?
        refute codespace.deleted? #should not be soft deleted for 7 days.
      end

      test "does not queue clean up for public repos" do
        codespace = create(:codespace, repository: create(:public_repository, owner: @org))
        Codespaces::CleanUpInaccessibleJob.expects(:perform_after_waiting_period).with(waiting_period: 7.days, codespace: codespace).never

        perform_enqueued_jobs(only: [
          Codespaces::OrgSettingsChangedJob,
          CodespacesProcessSystemEventJob,
          Codespaces::CleanUpInaccessibleJob,
          CodespacesSuspendEnvironmentJob]) do
          Codespaces::ProcessBusinessEnablementChange.call(
            business: @business,
            actor: @user,
            enablement: Codespaces::EnablementPolicyInputPresenter::DISABLED
          )
        end

        assert codespace.reload.accessible?
      end
    end

    context "when all codespaces are enabled", skip_enterprise: true do
      test "should not enqueue expected jobs when no new orgs to enable " do
        repo = create(:private_repository, owner: @org)
        other_user = create(:user)
        repo.add_member(other_user, action: :admin)
        codespace = create(:codespace, repository: repo)
        codespace.update(owner: other_user, billable_owner: other_user)

        CodespacesProcessSystemEventJob.expects(:perform_later).with(codespaces: [codespace]).never
        perform_enqueued_jobs(only: [
          Codespaces::OrgSettingsChangedJob,
          CodespacesProcessSystemEventJob,
          Codespaces::CleanUpInaccessibleJob,
          CodespacesSuspendEnvironmentJob]) do
            Codespaces::ProcessBusinessEnablementChange.call(
              business: @business,
              actor: @user,
              enablement: Codespaces::EnablementPolicyInputPresenter::ALL_ENTITIES
            )
          end
      end

      test "should enqueue expected jobs when new orgs to enable - disable to enable " do
        repo = create(:private_repository, owner: @org)
        other_user = create(:user)
        repo.add_member(other_user, action: :admin)
        codespace = create(:codespace, repository: repo)
        codespace.update(owner: other_user, billable_owner: other_user)
        Codespaces::BusinessDelegator.new(@business).disable_codespaces!

        CodespacesProcessSystemEventJob.expects(:perform_later).with(codespaces: [codespace])
        perform_enqueued_jobs(only: [
          Codespaces::OrgSettingsChangedJob,
          CodespacesProcessSystemEventJob,
          Codespaces::CleanUpInaccessibleJob,
          CodespacesSuspendEnvironmentJob]) do
            Codespaces::ProcessBusinessEnablementChange.call(
              business: @business,
              actor: @user,
              enablement: Codespaces::EnablementPolicyInputPresenter::ALL_ENTITIES
            )
          end
      end

      test "should enqueue expected jobs when new orgs to enable - selected to enable " do
        repo = create(:private_repository, owner: @org)
        repo.add_member(@user, action: :admin)
        already_enabled_codespace = create(:codespace, repository: repo)
        already_enabled_codespace.update(owner: @user, billable_owner: @user)

        repo2 = create(:private_repository, owner: @org2)
        other_user = create(:user)
        repo2.add_member(other_user, action: :admin)
        codespace = create(:codespace, repository: repo2)
        codespace.update(owner: other_user, billable_owner: other_user)
        Codespaces::BusinessDelegator.new(@business).enable_codespaces_for_selected_organizations!([@org.id])

        CodespacesProcessSystemEventJob.expects(:perform_later).with(codespaces: [codespace])
        perform_enqueued_jobs(only: [
          Codespaces::OrgSettingsChangedJob,
          CodespacesProcessSystemEventJob,
          Codespaces::CleanUpInaccessibleJob,
          CodespacesSuspendEnvironmentJob]) do
            Codespaces::ProcessBusinessEnablementChange.call(
              business: @business,
              actor: @user,
              enablement: Codespaces::EnablementPolicyInputPresenter::ALL_ENTITIES
            )
          end
      end
    end

    context "when codespaces selected codespaces are enabled", skip_enterprise: true do
      test "should switch to selected orgs with no orgs selected" do
        Codespaces::BusinessDelegator.new(@business).enable_codespaces_for_all_organizations!

        repo = create(:private_repository, owner: @org)
        other_user = create(:user)
        repo.add_member(other_user, action: :admin)
        codespace = create(:codespace, repository: repo)
        codespace.update(owner: other_user, billable_owner: other_user)

        Codespaces::CleanUpInaccessibleJob.expects(:perform_after_waiting_period).with(waiting_period: 7.days, codespace: codespace, reason: Codespace.deletion_reasons[:process_system_event])

        perform_enqueued_jobs(only: [
          Codespaces::OrgSettingsChangedJob,
          CodespacesProcessSystemEventJob,
          Codespaces::CleanUpInaccessibleJob,
          CodespacesSuspendEnvironmentJob]) do
            Codespaces::ProcessBusinessEnablementChange.call(
              business: @business,
              actor: @user,
              enablement: Codespaces::EnablementPolicyInputPresenter::SELECTED_ENTITIES,
              orgs_to_update: {}.to_json
            )
          end

        refute codespace.reload.accessible?
        assert Codespaces::BusinessDelegator.new(@business).codespaces_enabled_for_selected_organizations?
      end
      test "queues soft delete for any non-selected orgs - from enabled" do
        Codespaces::BusinessDelegator.new(@business).enable_codespaces_for_all_organizations!

        repo = create(:private_repository, owner: @org)
        other_user = create(:user)
        repo.add_member(other_user, action: :admin)
        codespace = create(:codespace, repository: repo)
        codespace.update(owner: other_user, billable_owner: other_user)

        repo2 = create(:private_repository, owner: @org2)
        user3 = create(:user)
        repo2.add_member(user3, action: :admin)
        codespace_to_keep = create(:codespace, repository: repo2)
        codespace_to_keep.update(owner: user3, billable_owner: user3)

        assert codespace_to_keep.reload.accessible?

        Codespaces::CleanUpInaccessibleJob.expects(:perform_after_waiting_period).with(waiting_period: 7.days, codespace: codespace, reason: Codespace.deletion_reasons[:process_system_event])
        Codespaces::CleanUpInaccessibleJob.expects(:perform_after_waiting_period).with(waiting_period: 7.days, codespace: codespace_to_keep, reason: Codespace.deletion_reasons[:process_system_event]).never

        perform_enqueued_jobs(only: [
          Codespaces::OrgSettingsChangedJob,
          CodespacesProcessSystemEventJob,
          Codespaces::CleanUpInaccessibleJob,
          CodespacesSuspendEnvironmentJob]) do
            Codespaces::ProcessBusinessEnablementChange.call(
              business: @business,
              actor: @user,
              enablement: Codespaces::EnablementPolicyInputPresenter::SELECTED_ENTITIES,
              orgs_to_update: { @org2.id => "enable" }.to_json
            )
          end

        refute codespace.reload.accessible?
      end
    end
    context "audit log", skip_enterprise: true do
      test "instruments audit log: codespaces.business_enablement_updated event - selected orgs" do
        Codespaces::BusinessDelegator.new(@business).enable_codespaces_for_all_organizations!

        repo = create(:private_repository, owner: @org)
        other_user = create(:user)
        repo.add_member(other_user, action: :admin)
        codespace = create(:codespace, repository: repo)
        codespace.update(owner: other_user, billable_owner: other_user)

        repo2 = create(:private_repository, owner: @org2)
        user3 = create(:user)
        repo2.add_member(user3, action: :admin)
        codespace_to_keep = create(:codespace, repository: repo2)
        codespace_to_keep.update(owner: user3, billable_owner: user3)

        events = subscribe "codespaces.business_enablement_updated"

        Codespaces::ProcessBusinessEnablementChange.call(
          business: @business,
          actor: @user,
          enablement: Codespaces::EnablementPolicyInputPresenter::SELECTED_ENTITIES,
          orgs_to_update: { @org2.id => "enable" }.to_json
        )

        expected_payload = {
          actor_id: @user.id,
          business: @business.name,
          business_id: @business.id,
          organization_names: [@org.name],
          enablement: "disabled",
        }

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end

      test "instruments audit log: codespaces.business_enablement_updated event - all orgs" do
        repo = create(:private_repository, owner: @org)
        other_user = create(:user)
        repo.add_member(other_user, action: :admin)
        create(:codespace, repository: repo)
        Codespaces::BusinessDelegator.new(@business).disable_codespaces!

        events = subscribe "codespaces.business_enablement_updated"

        Codespaces::ProcessBusinessEnablementChange.call(
          business: @business,
          actor: @user,
          enablement: Codespaces::EnablementPolicyInputPresenter::ALL_ENTITIES
        )

        expected_payload = {
          actor_id: @user.id,
          business: @business.name,
          business_id: @business.id,
          enablement: "all-orgs-enabled",
        }

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end
    end
  end
end
