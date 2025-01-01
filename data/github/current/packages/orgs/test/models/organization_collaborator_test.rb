# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationCollaboratorTest < GitHub::TestCase
  include HydroMessageJobTestHelpers

  fixtures do
    @admin = create(:user)
    @org = create(:organization, admins: [@admin])
    @owner = create(:user)
    @business = create(:business, organizations: [@org], owners: [@owner])

    @org.allow_private_repository_forking(actor: @admin)

    @repo = create(:private_repository, owner: @org)
    @collab1 = create(:user)
    @repo.add_member(@collab1)

    @public_repo = create(:public_repository, owner: @org)
    @public_collab1 = create(:user)
    @public_repo.add_member(@public_collab1)
    @forker = create(:user)
    @org.add_member(@forker)

    private_repo = create(:private_repository, owner: @org)
    @private_repo_fork, reason = private_repo.fork(forker: @forker)

    public_repo = create(:public_repository, owner: @org)
    @public_repo_fork, reason = public_repo.fork(forker: @forker)

    @collab = create(:user)
  end

  setup do
    OrganizationCollaborator.destroy_all
  end

  context ".backfill_for_org" do
    test "creates records for all collaborators in the org" do
      assert_difference "OrganizationCollaborator.count", +2 do
        OrganizationCollaborator.backfill_for_org(@org)
      end

      oc1 = OrganizationCollaborator.with_org_and_user(@org, @collab1).first!
      refute_nil oc1
      refute oc1.public?
      assert oc1.private?

      public_oc1 = OrganizationCollaborator.with_org_and_user(@org, @public_collab1).first!
      refute_nil public_oc1
      assert public_oc1.public?
      refute public_oc1.private?
    end

    test "removes record when user is no longer a collaborator on any repo" do
      GitHub.flipper[:collaborator_cache_write].disable
      GitHub.flipper[:collaborator_cache_read].disable
      OrganizationCollaborator.backfill_for_org(@org)

      refute_nil OrganizationCollaborator.with_org_and_user(@org, @public_collab1).first
      @public_repo.remove_member(@public_collab1)
      assert_difference "OrganizationCollaborator.count", -1 do
        OrganizationCollaborator.backfill_for_org(@org)
      end
      assert_nil OrganizationCollaborator.with_org_and_user(@org, @public_collab1).first
    end

    test "updates public and private attributes" do
      OrganizationCollaborator.backfill_for_org(@org)

      oc1 = OrganizationCollaborator.with_org_and_user(@org, @collab1).first!
      refute_nil oc1
      refute oc1.public?
      assert oc1.private?
      @public_repo.add_member(@collab1)
      @repo.remove_member(@collab1)
      assert_no_difference "OrganizationCollaborator.count" do
        OrganizationCollaborator.backfill_for_org(@org)
      end
      oc1 = OrganizationCollaborator.with_org_and_user(@org, @collab1).first!
      refute_nil oc1
      assert oc1.public?
      refute oc1.private?
    end

    test "only private forks attributes" do
      GitHub.flipper[:collaborator_cache_write].disable
      GitHub.flipper[:collaborator_cache_read].disable
      @private_repo_fork.add_member(@collab)

      assert_difference "OrganizationCollaborator.count", +3 do
        OrganizationCollaborator.backfill_for_org(@org)
      end

      oc = OrganizationCollaborator.with_org_and_user(@org, @collab).first!
      refute_nil oc
      refute oc.public?
      refute oc.public_only_forks?
      refute oc.private?
      assert oc.private_only_forks?
    end
  end

  context "update_for_org_and_user" do
    test "creates record if user is added as a first time collaborator" do
      @repo.add_member(@collab)
      oc = OrganizationCollaborator.update_for_org_and_user(@org, @collab)
      refute_nil oc
      refute oc&.public?
      refute oc&.public_only_forks?
      assert oc&.private?
      refute oc&.private_only_forks?
    end

    test "removes record if user is no longer a collaborator" do
      oc = OrganizationCollaborator.update_for_org_and_user(@org, @collab1)
      refute_nil oc

      @repo.remove_member(@collab1)
      oc = OrganizationCollaborator.update_for_org_and_user(@org, @collab1)
      assert_nil oc
      oc = OrganizationCollaborator.with_org_and_user(@org, @collab1).first
      assert_nil oc
    end

    test "updates records when user collab status changes" do
      @repo.add_member(@collab)
      oc = OrganizationCollaborator.update_for_org_and_user(@org, @collab)
      refute_nil oc
      refute oc&.public?
      assert oc&.private?

      @public_repo.add_member(@collab)
      oc = OrganizationCollaborator.update_for_org_and_user(@org, @collab)
      refute_nil oc
      assert oc&.public?
      assert oc&.private?
    end
  end

  context "update events" do
    test "removes collaborator when user gets added to org" do
      GitHub.flipper[:collaborator_cache_write].enable
      OrganizationCollaborator.backfill_for_org(@org)
      oc = OrganizationCollaborator.with_org_and_user(@org, @collab1).first
      refute_nil oc

      @org.add_member(@collab1)

      oc = OrganizationCollaborator.with_org_and_user(@org, @collab1).first
      assert_nil oc
    end

    test "removes collaborator when user gets bulk added to org" do
      GitHub.flipper[:collaborator_cache_write].enable
      OrganizationCollaborator.backfill_for_org(@org)
      oc = OrganizationCollaborator.with_org_and_user(@org, @collab1).first
      refute_nil oc

      perform_enqueued_jobs only: OrganizationOrchestrationJob do
        @org.bulk_add_members([@collab1])
      end

      oc = OrganizationCollaborator.with_org_and_user(@org, @collab1).first
      assert_nil oc
    end

    test "creates collaborator when user gets added to repo in account with write enabled" do
      GitHub.flipper[:collaborator_cache_write].enable
      @repo.add_member(@collab)
      oc = OrganizationCollaborator.with_org_and_user(@org, @collab).first
      refute_nil oc
    end

    test "removes collaborator when user gets removed from repo" do
      GitHub.flipper[:collaborator_cache_write].enable
      OrganizationCollaborator.backfill_for_org(@org)
      oc1 = OrganizationCollaborator.with_org_and_user(@org, @collab1).first
      refute_nil oc1

      @repo.remove_member(@collab1)

      oc1 = OrganizationCollaborator.with_org_and_user(@org, @collab1).first
      assert_nil oc1
    end

    test "removes collaborator when remove_outside_collaborator is called" do
      GitHub.flipper[:collaborator_cache_write].enable
      OrganizationCollaborator.backfill_for_org(@org)
      oc = OrganizationCollaborator.with_org_and_user(@org, @collab1).first
      refute_nil oc

      @org.remove_outside_collaborator!(@collab1)

      oc = OrganizationCollaborator.with_org_and_user(@org, @collab1).first
      assert_nil oc
    end

    test "creates collaborator when convert_to_outside_collaborator is called" do
      GitHub.flipper[:collaborator_cache_write].enable
      GitHub.flipper[:org_remove_member_cleanup_in_bulk_test_only].disable
      member = create(:user)
      @org.add_member(member)
      team = create(:team, organization: @org)
      team.add_repository(@repo, :pull)
      team.add_repository(@public_repo, :pull)
      team.add_member(member)
      oc = OrganizationCollaborator.with_org_and_user(@org, member).first
      assert_nil oc

      perform_enqueued_jobs only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob] do
        @org.convert_to_outside_collaborator!(member)
      end

      oc = OrganizationCollaborator.with_org_and_user(@org, member).first
      refute_nil oc
      assert oc&.public?
      assert oc&.private?
    end

    test "removes collaborators when repos are soft-deleted" do
      GitHub.flipper[:collaborator_cache_write].enable
      OrganizationCollaborator.backfill_for_org(@org)
      oc = OrganizationCollaborator.with_org_and_user(@org, @collab1).first
      refute_nil oc

      perform_enqueued_jobs only: [OrganizationCollaboratorBackfillJob, RepositoryOrchestrationJob] do
        perform_enqueued_hydro_jobs only: [HydroOrganizationCollaboratorUpdateOnRepoChangeJob] do
          @repo.remove(@owner)
        end
      end

      oc = OrganizationCollaborator.with_org_and_user(@org, @collab1).first
      assert_nil oc
    end

    unless GitHub.single_business_environment?
      test "updates collaborators when org is added to a business" do
        GitHub.flipper[:collaborator_cache_write].enable
        OrganizationCollaborator.backfill_for_org(@org)
        business = create(:business)
        @business.remove_organization(@org)
        business.add_organization(@org)
        oc = OrganizationCollaborator.with_org_and_user(@org, @collab1).first
        refute_nil oc
        assert_equal business.id, oc&.business_id
      end

      test "updates collaborators when org is removed from a business" do
        GitHub.flipper[:collaborator_cache_write].enable
        OrganizationCollaborator.backfill_for_org(@org)
        @business.remove_organization(@org)
        oc = OrganizationCollaborator.with_org_and_user(@org, @collab1).first
        refute_nil oc
        assert_nil oc&.business_id
      end
    end
  end
end
