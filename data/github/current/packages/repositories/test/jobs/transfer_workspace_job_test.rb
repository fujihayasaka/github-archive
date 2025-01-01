# typed: true
# frozen_string_literal: true

require "test_helper"

class TransferWorkspaceJobTest < GitHub::TestCase
  fixtures do
    @owner = create(:paid_user, login: "owner")
    @org   = create(:organization, login: "acme", admin: @owner)

    @repository = create(:private_repository, name: "acme", owner: @org)

    @advisory = create(:repository_advisory, repository: @repository)
    @advisory2 = create(:repository_advisory, repository: @repository)
    # Make sure we run the ability setup background job
    GitHub.context.push(actor_id: @owner.id)
    RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(@advisory, @owner).save!
    RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(@advisory2, @owner).save!
    refute_nil @workspace = @advisory.workspace_repository
    refute_nil @conflicting_workspace = @advisory2.workspace_repository

    @new_owner = create(:paid_user, login: "new-owner")
    @new_org   = create(:organization, login: "new-corp", admin: @new_owner)

    @conflicting_repo = create(:private_repository, name: @conflicting_workspace.name, owner: @new_org)
  end

  setup do
    @repository.transfer_ownership_to(@new_org, actor: @owner)

    # The Repository has changed ownership
    assert_equal_owner @new_org, @repository.owner

    # The new owner gains admin abilities
    assert @repository.adminable_by?(@new_owner)

    # The old owner loses admin abilities
    refute @repository.adminable_by?(@owner)
  end

  test "ownership of workspaces are correctly transferred" do
    assert_equal @org, @workspace.owner
    assert @workspace.adminable_by?(@owner)
    refute @workspace.adminable_by?(@new_owner)

    # Ensure we run follow-up background jobs from the transfer
    TransferWorkspaceJob.perform_now(@workspace.id)
    @workspace.reload

    assert_equal @new_org, @workspace.owner
    assert @workspace.adminable_by?(@new_owner)
    refute @workspace.adminable_by?(@owner)
  end

  test "ownership of workspaces with conflicting names is correctly transferred" do
    assert_equal @org, @conflicting_workspace.owner
    assert @conflicting_workspace.adminable_by?(@owner)
    refute @conflicting_workspace.adminable_by?(@new_owner)

    # Ensure we run follow-up background jobs from the transfer
    TransferWorkspaceJob.perform_now(@conflicting_workspace.id)
    @conflicting_workspace.reload

    assert_equal @new_org, @conflicting_workspace.owner
    assert @conflicting_workspace.adminable_by?(@new_owner)
    refute @conflicting_workspace.adminable_by?(@owner)
  end
end
