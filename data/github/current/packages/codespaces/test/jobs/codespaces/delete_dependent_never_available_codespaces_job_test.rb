# typed: true
# frozen_string_literal: true

require "test_helper"

class DeleteDependentNeverAvailableCodespacesJobTest < GitHub::TestCase
  include HydroTestHelpers

  context "DeleteDependentNeverAvailableCodespacesJob" do

    test "deletes only codespaces that are stuck in provisioning in vscs for a specific owner", skip_enterprise: true do
      owner = create(:user)
      codespaces = create_list(:codespace, 2, :provisioning_in_vscs, owner: owner)

      provisioned_codespace = create(:codespace, owner: owner)
      other_owner_codespace = create(:codespace, :provisioning_in_vscs)

      Codespaces::DeleteDependentNeverAvailableCodespacesJob.perform_now(owner_id: owner.id)
      codespaces.each do |codespace|
        assert_enqueued_with(job: CodespacesDeleteJob, args: [{ codespace: codespace, reason: Codespace.deletion_reasons[:dependent_never_available] }])
      end
      assert_enqueued_jobs 2, only: CodespacesDeleteJob
    end

    test "deletes only codespaces that are failed in vscs for a specific owner", skip_enterprise: true do
      owner = create(:user)
      codespaces = create_list(:codespace, 2, :failed_in_vscs, owner: owner)

      provisioned_codespace = create(:codespace, owner: owner)
      other_owner_codespace = create(:codespace, :failed_in_vscs)

      Codespaces::DeleteDependentNeverAvailableCodespacesJob.perform_now(owner_id: owner.id)
      codespaces.each do |codespace|
        assert_enqueued_with(job: CodespacesDeleteJob, args: [{ codespace: codespace, reason: Codespace.deletion_reasons[:dependent_never_available] }])
      end
      assert_enqueued_jobs 2, only: CodespacesDeleteJob
    end

    test "deletes codespaces for a when the given id is the billable owner", skip_enterprise: true do
      owner = create(:user)
      codespaces = create_list(:codespace, 2, :provisioning_in_vscs, billable_owner: owner)

      provisioned_codespace = create(:codespace, billable_owner: owner)
      other_owner_codespace = create(:codespace, :provisioning_in_vscs)

      Codespaces::DeleteDependentNeverAvailableCodespacesJob.perform_now(owner_id: owner.id)
      codespaces.each do |codespace|
        assert_enqueued_with(job: CodespacesDeleteJob, args: [{ codespace: codespace, reason: Codespace.deletion_reasons[:dependent_never_available] }])
      end
      assert_enqueued_jobs 2, only: CodespacesDeleteJob
    end

    test "shows the appropriate reason for deprovisioning codespaces", skip_enterprise: true do
      GitHub.flipper[:codespaces_pause_deletions_dependent_never_available].disable
      owner = create(:user)
      codespaces = create_list(:codespace, 2, :provisioning_in_vscs, owner: owner)

      Codespaces::DeleteDependentNeverAvailableCodespacesJob.perform_now(owner_id: owner.id)
      perform_enqueued_jobs(only: CodespacesDeleteJob)

      codespaces.each do |codespace|
        assert codespace.reload.deleted?
        message = {
          codespace: Hydro::EntitySerializer.codespace(codespace),
          reason: Codespace.deletion_reasons[:dependent_never_available],
        }
        assert_hydro_published(message, schema: "github.codespaces.v0.CodespaceSoftDeleted")
      end
    end
  end
end
