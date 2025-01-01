# typed: true
# frozen_string_literal: true

require "test_helper"

class DeleteDependentCodespacesJobTest < GitHub::TestCase
  include HydroTestHelpers

  context "DeleteDependentCodespacesJob" do

    test "Enqueued when owner is destroyed", skip_enterprise: true do
      deleted_owner = create(:organization)
      not_deleted_owner = create(:organization)

      Codespaces::DeleteDependentCodespacesJob.expects(:perform_later).with(owner_id: deleted_owner.id)

      Codespaces::DeleteDependentCodespacesJob.expects(:perform_later).with(owner_id: not_deleted_owner.id).never

      deleted_owner.destroy
    end

    test "Enqueues deletion of owned codespaces when user is deleted", skip_enterprise: true do
      owner = create(:user)
      codespaces = create_list(:codespace, 2, owner: owner)
      other_codespace = create(:codespace)

      Codespaces::DeleteDependentCodespacesJob.perform_now(owner_id: owner.id)
      codespaces.each do |codespace|
        assert_enqueued_with(job: CodespacesDeleteJob, args: [{ codespace: codespace, reason: Codespace.deletion_reasons[:bulk_dependent_deletion] }])
      end
      assert_enqueued_jobs 2, only: CodespacesDeleteJob
    end

    test "Enqueues deletion of owned codespaces when billable owner is deleted", skip_enterprise: true do
      owner = create(:user)
      organization = create(:organization)
      codespaces = create_list(:codespace, 2, owner: owner, billable_owner: organization)
      other_codespace = create(:codespace)

      Codespaces::DeleteDependentCodespacesJob.perform_now(owner_id: organization.id)

      codespaces.each do |codespace|
        assert_enqueued_with(job: CodespacesDeleteJob, args: [{ codespace: codespace, reason: Codespace.deletion_reasons[:bulk_dependent_deletion] }])
      end
      assert_enqueued_jobs 2, only: CodespacesDeleteJob
    end

    test "Deletes codespace if queued for previously deleted user", skip_enterprise: true do
      owner = create(:user)
      codespaces = create_list(:codespace, 2, owner: owner)
      owner.delete

      # when the model callback isn't called
      Codespaces::DeleteDependentCodespacesJob.expects(:perform_later).with(owner_id: owner.id).never

      # when we queue the job manually
      Codespaces::DeleteDependentCodespacesJob.perform_now(owner_id: owner.id)

      assert_enqueued_jobs 2, only: CodespacesDeleteJob
    end

    test "Specifies the appropriate reason for deletion", skip_enterprise: true do
      GitHub.flipper[:codespaces_pause_deletions_bulk_dependent_deletion].disable
      owner = create(:user)
      codespace = create(:codespace, owner: owner)

      # when we queue the job manually
      Codespaces::DeleteDependentCodespacesJob.perform_now(owner_id: owner.id)

      perform_enqueued_jobs(only: CodespacesDeleteJob)

      assert codespace.reload.deleted?
      message = {
        codespace: Hydro::EntitySerializer.codespace(codespace),
        reason: Codespace.deletion_reasons[:bulk_dependent_deletion],
      }
      assert_hydro_published(message, schema: "github.codespaces.v0.CodespaceSoftDeleted")
    end
  end
end
