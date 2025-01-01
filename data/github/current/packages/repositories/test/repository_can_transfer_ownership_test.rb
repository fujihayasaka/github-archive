# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryCanTransferOwnershipTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @other_user = create(:user)

    @org = create(:organization)
    @org.add_member(@user)
    @org_public_repo = create(:repository, owner: @org)
    @org_public_fork = create(:fork_repository, forker: @user, fork_repo: @org_public_repo)
    @org_private_repo = create(:private_repository, owner: @org)
    @org_private_repo.allow_private_repository_forking(actor: @org.admin)
    @org_private_fork = create(:fork_repository, forker: @user, fork_repo: @org_private_repo)

    @private_repo = create(:private_repository, owner: @user)
    @private_repo.add_member(@other_user)
    @private_fork = create(:fork_repository, forker: @other_user, fork_repo: @private_repo)

    @internal_repo = create(:internal_repository)
    admin = @internal_repo.owner.admins.first
    @internal_repo.allow_private_repository_forking(actor: admin)
    @internal_fork = create(:fork_repository, forker: admin, fork_repo: @internal_repo)
  end

  test "returns false if owned by a trade_controls_read_only is true" do
    assert @org_public_repo.can_transfer_ownership?

    @org.trade_controls_restriction.full!

    @org_public_repo.reload

    refute @org_public_repo.can_transfer_ownership?
    assert @org_public_repo.trade_controls_read_only?
  end

  test "returns true if owned by a partial trade controls org" do
    assert @org_public_repo.can_transfer_ownership?

    @org.trade_controls_restriction.partial!

    @org_public_repo.reload

    assert @org_public_repo.can_transfer_ownership?
  end

  test "allowed for public roots" do
    assert @org_public_repo.can_transfer_ownership?
  end

  test "allowed for public forks" do
    assert @org_public_fork.can_transfer_ownership?
  end

  test "allowed for private roots" do
    assert @private_repo.can_transfer_ownership?
    assert @org_private_repo.can_transfer_ownership?
  end

  test "not allowed for private forks" do
    refute @org_private_fork.can_transfer_ownership?
    refute @private_fork.can_transfer_ownership?
  end
end
