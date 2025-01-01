# typed: true
# frozen_string_literal: true

require "test_helper"

class CleanUpInaccessibleJobTest < GitHub::TestCase
  include HydroTestHelpers

  test "it locks duplicate jobs for 7 days" do
    repository = create(:private_repository)
    repository.block_private_repository_forking(actor: repository.owner)
    inaccessible = create(:inaccessible_codespace, repository: repository)

    job = Codespaces::CleanUpInaccessibleJob.perform_later(codespace: inaccessible)
    dup_job = Codespaces::CleanUpInaccessibleJob.perform_later(codespace: inaccessible)

    assert Codespaces::CleanUpInaccessibleJob.lock_timeout == 7.days
    refute dup_job
  end

  test "Specifies the appropriate reason for deprovisioning", skip_enterprise: true do
    GitHub.flipper[:codespaces_pause_deletions_inaccessible].disable
    repository = create(:private_repository)
    repository.block_private_repository_forking(actor: repository.owner)
    inaccessible = create(:inaccessible_codespace, repository: repository)

    Codespaces::CleanUpInaccessibleJob.perform_now(codespace: inaccessible)

    perform_enqueued_jobs(only: CodespacesDeleteJob)

    assert inaccessible.reload.deleted?
    message = {
      codespace: Hydro::EntitySerializer.codespace(inaccessible),
      reason: Codespace.deletion_reasons[:inaccessible],
    }
    assert_hydro_published(message, schema: "github.codespaces.v0.CodespaceSoftDeleted")
  end

  test "alternate deletion reason for deprovisioning", skip_enterprise: true do
    GitHub.flipper[:codespaces_pause_deletions_process_system_event].disable
    repository = create(:private_repository)
    repository.block_private_repository_forking(actor: repository.owner)
    inaccessible = create(:inaccessible_codespace, repository: repository)

    Codespaces::CleanUpInaccessibleJob.perform_now(codespace: inaccessible, reason: Codespace.deletion_reasons[:process_system_event])

    perform_enqueued_jobs(only: CodespacesDeleteJob)

    assert inaccessible.reload.deleted?
    message = {
      codespace: Hydro::EntitySerializer.codespace(inaccessible),
      reason: Codespace.deletion_reasons[:process_system_event],
    }
    assert_hydro_published(message, schema: "github.codespaces.v0.CodespaceSoftDeleted")
  end

  context "when the codespace is unbillable", skip_enterprise: true do
    test "enqueues deletion of the codespace" do
      repository = create(:private_repository)
      repository.block_private_repository_forking(actor: repository.owner)
      inaccessible = create(:inaccessible_codespace, repository: repository)

      CodespacesDeleteJob.expects(:perform_later).with(codespace: inaccessible, reason: Codespace.deletion_reasons[:inaccessible])

      Codespaces::CleanUpInaccessibleJob.perform_now(codespace: inaccessible)
    end
  end

  context "when the codespace has become billable again", skip_enterprise: true do
    test "does not enqueue deletion of the codespace" do
      accessible = create(:codespace)

      CodespacesDeleteJob.expects(:perform_later).with(codespace: accessible).never

      Codespaces::CleanUpInaccessibleJob.perform_now(codespace: accessible)
    end
  end
end unless GitHub.enterprise?
