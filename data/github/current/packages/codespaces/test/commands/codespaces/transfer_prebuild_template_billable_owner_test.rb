# typed: true
# frozen_string_literal: true

require "test_helper"

module Codespaces
  class TransferPrebuildTemplateBillableOwnerTest < GitHub::TestCase
    include CodespacesPlanFixtures

    fixtures do
      @org = create(:codespaces_organization)
      @private_repo = create(:private_repository, owner: @org)
      @public_repo = create(:repository, owner: @org)
      @prebuild_template = create(:codespace_prebuild_template, repository: @private_repo)
    end

    test "it should noop and return false if the prebuild template was deleted" do
      billing_entry = create(
        :codespace_prebuild_template_billing_entry,
        prebuild_template: @prebuild_template,
        billable_owner: @org
      )

      assert_equal billing_entry.billable_owner, @org

      guid = @prebuild_template.guid

      @prebuild_template.destroy!
      billing_entry.prebuild_deleted_at = Time.now
      billing_entry.save!

      refute Codespaces::TransferPrebuildTemplateBillableOwner.call(guid)

      latest_billing_entry = Codespaces::PrebuildTemplateBillingEntry.latest(guid)

      assert_equal @org.id, latest_billing_entry.billable_owner_id
      assert_equal billing_entry, latest_billing_entry
    end

    test "it should transfer billable owner to new owner" do
      events = subscribe "codespaces.prebuild_template_transfer_ownership"
      billing_entry = create(
        :codespace_prebuild_template_billing_entry,
        prebuild_template: @prebuild_template,
        billable_owner: @org
      )

      assert_equal billing_entry.billable_owner, @org

      new_org = create(:codespaces_organization)
      repo = billing_entry.repository
      repo.owner = new_org
      repo.save!

      old_billable_owner = billing_entry.billable_owner
      new_billable_owner = repo.owner
      refute_equal old_billable_owner, new_billable_owner
      assert new_billable_owner, new_org

      assert Codespaces::TransferPrebuildTemplateBillableOwner.call(@prebuild_template.guid)

      latest_billing_entry = Codespaces::PrebuildTemplateBillingEntry.latest(@prebuild_template.guid)

      assert_equal latest_billing_entry.billable_owner, new_billable_owner
      refute_equal billing_entry, latest_billing_entry

      expected_payload = {
        old_billable_owner_id: old_billable_owner.id,
        old_billable_owner_login: old_billable_owner&.login,
        new_billable_owner_id: new_billable_owner.id,
        new_billable_owner_login: new_billable_owner&.login,
        plan_name: latest_billing_entry.prebuild_plan_name,
        environment_id: latest_billing_entry.prebuild_template_guid
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end
  end
end
