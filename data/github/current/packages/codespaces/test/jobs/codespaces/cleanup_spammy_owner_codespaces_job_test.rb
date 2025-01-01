# typed: true
# frozen_string_literal: true

require "test_helper"

class CleanupSpammyOwnerCodespacesJobTest < GitHub::TestCase

  context "CleanupSpammyOwnerCodespacesJob" do

    test "deletes spammy owner's codespaces", skip_enterprise: true do
      owner = create(:user)
      codespaces = create_list(:codespace, 2, :provisioning_in_vscs, owner: owner)
      owner.mark_as_spammy

      other_owner_codespace = create(:codespace)

      codespaces.each do |codespace|
        CodespacesDeleteJob.expects(:perform_later).with(codespace: codespace, reason: Codespace.deletion_reasons[:bulk_dependent_deletion])
      end

      CodespacesDeleteJob.expects(:perform_later).with(codespace: other_owner_codespace).never

      Codespaces::CleanupSpammyOwnerCodespacesJob.perform_now(owner_id: owner.id, owner_type: owner.type)
    end

    test "deletes spammy billable owner's codespaces", skip_enterprise: true do
      owner = create(:user)
      codespaces = create_list(:codespace, 2, :provisioning_in_vscs, billable_owner: owner)
      owner.mark_as_spammy

      codespaces.each do |codespace|
        CodespacesDeleteJob.expects(:perform_later).with(codespace: codespace, reason: Codespace.deletion_reasons[:bulk_dependent_deletion])
      end

      Codespaces::CleanupSpammyOwnerCodespacesJob.perform_now(owner_id: owner.id, owner_type: owner.type)
    end

    test "does not delete codespaces when neither owner or billable_owner are spammy", skip_enterprise: true do
      owner = create(:user)
      codespaces = create_list(:codespace, 2, :provisioning_in_vscs, owner: owner, billable_owner: owner)

      codespaces.each do |_codespace|
        CodespacesDeleteJob.expects(:perform_later).never
      end

      Codespaces::CleanupSpammyOwnerCodespacesJob.perform_now(owner_id: owner.id, owner_type: owner.type)
    end

    test "does not fail when owner has been deleted", skip_enterprise: true do
      owner = create(:user)
      codespaces = create_list(:codespace, 2, :provisioning_in_vscs, owner: owner, billable_owner: owner)
      owner.destroy!

      Codespaces::CleanupSpammyOwnerCodespacesJob.perform_now(owner_id: owner.id, owner_type: owner.type)
    end
  end
end
