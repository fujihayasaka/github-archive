# typed: true
# frozen_string_literal: true

require "test_helper"

class RemoveForksForInaccessibleRepositoriesJobTest < GitHub::TestCase

  fixtures do
    # Create org1 in an enterprise
    @org1 = create(:organization)
    @member = create(:user)
    @org1.add_member(@member)
    @business = @org1.business || create(:business)
    @business.add_organization(@org1)
    @org1.allow_private_repository_forking(actor: @org1.admin, policy: Configurable::AllowPrivateRepositoryForking::LEGACY_ENABLED)
    @org1.reload

    # Create org2 in the same enterprise
    @org2 = create(:organization)
    @org2.add_admin(@org1.admin)
    @org2.business = @business

    # Create an internal repo in org1
    @internal_repo = create(:internal_repository, owner: @org1)

    # Create private repo for intra-org tests
    @private_repo = create(:private_repository, owner: @org1)
    @private_member_fork, reason = @private_repo.fork(forker: @member)
    @private_intra_org_fork, reason = @private_repo.fork(forker: @member, org: @org1)

    # Fork the internal repo in org1 into org2
    @internal_fork, reason = @internal_repo.fork(forker: @org1.admin, org: @org2)

    # Fork the internal repo in org1 into member
    @member_fork, reason = @internal_repo.fork(forker: @member)

    # Fork the internal repo in org1 into org1
    @internal_intra_org_fork, reason = @internal_repo.fork(forker: @member, org: @org1)

    # Remove member from org1
    perform_enqueued_jobs(only: [RevokeOrgMembershipAbilitiesJob]) do
      @org1.reload.remove_member!(@member)
    end
  end

  test "removes inaccessible member fork and leaves org fork" do
    assert_equal true, Repository.find_by!(id: @internal_repo.id).active?
    assert_equal true, Repository.find_by!(id: @internal_fork.id).active?
    assert_equal true, Repository.find_by!(id: @internal_intra_org_fork.id).active?
    assert_equal true, Repository.find_by!(id: @member_fork.id).active?

    RemoveForksForInaccessibleRepositoriesJob.perform_now([@internal_repo], [@member])

    assert_equal true, Repository.find_by!(id: @internal_repo.id).active?
    assert_equal true, Repository.find_by!(id: @internal_fork.id).active?
    assert_equal true, Repository.find_by!(id: @internal_intra_org_fork.id).active?
    assert_equal false, Repository.find_by!(id: @member_fork.id).active?
  end

  test "removes member fork, but leaves member's intra-org fork" do
    assert_equal true, Repository.find_by!(id: @private_repo.id).active?
    assert_equal true, Repository.find_by!(id: @private_member_fork.id).active?
    assert_equal true, Repository.find_by!(id: @private_intra_org_fork.id).active?

    RemoveForksForInaccessibleRepositoriesJob.perform_now([@private_repo], [@member])

    assert_equal true, Repository.find_by!(id: @private_repo.id).active?
    assert_equal true, Repository.find_by!(id: @private_intra_org_fork.id).active?
    assert_equal false, Repository.find_by!(id: @private_member_fork.id).active?
  end
end
