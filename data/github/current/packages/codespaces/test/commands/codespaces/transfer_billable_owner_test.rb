# typed: true
# frozen_string_literal: true

require "test_helper"

module Codespaces
  class TransferBillableOwnerTest < GitHub::TestCase
    fixtures do

      @user = create(:user)
      @org = create(:codespaces_organization, plan: GitHub::Plan.business)
      @private_repo = create(:private_repository, owner: @org)
      @public_repo = create(:repository, owner: @org)
      @org.add_member(@user)
    end

    test "it should noop and return false if the codespace owner evaluates to nil" do
      codespace = create(:codespace, repository: @private_repo)
      codespace.owner.destroy
      codespace.reload
      refute codespace.owner
      refute Codespaces::TransferBillableOwner.call(codespace)
    end

    test "it should noop and return false if the billable owner evaluates to nil" do
      codespace = create(:codespace, repository: @private_repo, owner: @user)
      orig_billable_owner = codespace.billable_owner

      assert_equal orig_billable_owner, @org

      @org.remove_member(@user)
      refute Codespaces::TransferBillableOwner.call(codespace)
      codespace.reload

      assert_equal orig_billable_owner, codespace.billable_owner
    end

    test "it should noop and return false if the billable owner evaluates to the same value" do
      codespace = create(:codespace, repository: @private_repo, owner: @user)
      orig_billable_owner = codespace.billable_owner

      assert_equal @org, orig_billable_owner

      refute Codespaces::TransferBillableOwner.call(codespace)
      codespace.reload

      assert_equal orig_billable_owner, codespace.billable_owner
    end

    test "it should transfer billable owner to new owner" do

      events = subscribe "codespaces.transfer_ownership"
      @org.update_organization_codespaces_ownership_setting(Configurable::OrganizationCodespacesOwnershipSetting::USER, actor: @user)
      codespace = create(:codespace, repository: @public_repo, owner: @user, enable_org_access: false)
      orig_billable_owner = codespace.billable_owner
      orig_billing_entry = codespace.billing_entry

      assert_equal @user, orig_billable_owner

      # enable org access
      Codespaces::OrgPolicy.grant_billing_permission!(@user, @org)
      @org.update_organization_codespaces_ownership_setting(Configurable::OrganizationCodespacesOwnershipSetting::ORGANIZATION, actor: @user)
      codespace.reload

      old_billable_owner = codespace.billable_owner
      new_billable_owner = Codespaces::RepositoryPolicy.async_with_prefill(codespace.owner, codespace.repository).sync.billable_owner
      refute_equal orig_billable_owner, new_billable_owner
      assert @org, new_billable_owner

      assert Codespaces::TransferBillableOwner.call(codespace)
      codespace.reload

      assert_equal codespace.billable_owner, new_billable_owner
      assert_equal codespace.billing_entry.billable_owner, new_billable_owner
      refute_equal orig_billing_entry, codespace.billing_entry

      expected_payload = {
        owner_id: codespace.owner_id,
        owner: codespace.owner.login,
        old_billable_owner_id: old_billable_owner.id,
        old_billable_owner_login: old_billable_owner&.login,
        new_billable_owner_id: new_billable_owner.id,
        new_billable_owner_login: new_billable_owner&.login,
        codespace_id: codespace.id,
        plan_id: codespace.plan_id,
        environment_id: codespace.guid,
        repo: codespace.repository.nwo,
        repo_id: codespace.repository_id,
        public_repo: codespace.repository.public?,
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "it includes the copilot_workspace_id in the new billing entry" do
      @org.update_organization_codespaces_ownership_setting(Configurable::OrganizationCodespacesOwnershipSetting::USER, actor: @user)
      cw = create(:copilot_workspace, repository: @public_repo, owner: @user, enable_org_access: false)
      orig_billable_owner = cw.billable_owner
      orig_billing_entry = cw.billing_entry

      assert_equal @user, orig_billable_owner

      # enable org access
      Codespaces::OrgPolicy.grant_billing_permission!(@user, @org)
      @org.update_organization_codespaces_ownership_setting(Configurable::OrganizationCodespacesOwnershipSetting::ORGANIZATION, actor: @user)
      cw.reload

      old_billable_owner = cw.billable_owner
      new_billable_owner = Codespaces::RepositoryPolicy.async_with_prefill(cw.owner, cw.repository).sync.billable_owner
      refute_equal orig_billable_owner, new_billable_owner
      assert @org, new_billable_owner

      assert Codespaces::TransferBillableOwner.call(cw)
      cw.reload

      assert_equal cw.billable_owner, new_billable_owner
      assert_equal cw.billing_entry.billable_owner, new_billable_owner
      refute_equal orig_billing_entry, cw.billing_entry
      assert_equal orig_billing_entry.copilot_workspace_id, cw.billing_entry.copilot_workspace_id
    end
  end unless GitHub.enterprise?
end
