# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class GrantSponsorsOnlyRepositoryAccessJobTest < GitHub::TestCase
  fixtures do
    @org_admin = create(:user)
    @org = create(:organization, :sponsorable, admin: @org_admin)
    @repo = create(:private_repository, owner: @org)

    @user_sponsorable = create(:user, :verified)
    @user_sponsors_listing = create(:sponsors_listing, :approved,
      sponsorable: @user_sponsorable)
    @repo.add_member(@user_sponsorable, @org_admin, action: :admin)

    @user_tier = create(:sponsors_tier, :published, sponsors_listing: @user_sponsors_listing, repository: @repo)
    @org_tier = create(:sponsors_tier, :published, sponsors_listing: @org.sponsors_listing, repository: @repo,
      creator: @org_admin)

    @sponsor_of_user = create(:sponsorship, sponsorable: @user_sponsorable, tier: @user_tier).sponsor
    @sponsor_of_org = create(:sponsorship, sponsorable: @org, tier: @org_tier).sponsor
  end

  setup do
    skip unless GitHub.sponsors_enabled?
  end

  context "#perform" do
    test "invites the sponsor of a user sponsorable to join a repo" do
      assert_difference(-> { RepositoryInvitation.count }) do
        GrantSponsorsOnlyRepositoryAccessJob.perform_now(@sponsor_of_user.id, @repo.id, @user_tier.id)
      end

      repo_invitation = RepositoryInvitation.last
      assert_equal @sponsor_of_user, T.must(repo_invitation).invitee
      assert_equal @repo, T.must(repo_invitation).repository
      assert_equal "read", T.must(repo_invitation).permissions
      refute_predicate repo_invitation, :invite_expired?
      assert_equal @user_tier.actor_for_repository_invitation, T.must(repo_invitation).inviter
      assert_sponsorship_repository_created_for(tier: @user_tier, sponsor: @sponsor_of_user)
    end

    test "invites the sponsor of an org sponsorable to join a repo" do
      assert_difference(-> { RepositoryInvitation.count }) do
        GrantSponsorsOnlyRepositoryAccessJob.perform_now(@sponsor_of_org.id, @repo.id, @org_tier.id)
      end

      repo_invitation = RepositoryInvitation.last
      assert_equal @sponsor_of_org, T.must(repo_invitation).invitee
      assert_equal @repo, T.must(repo_invitation).repository
      assert_equal "read", T.must(repo_invitation).permissions
      refute_predicate repo_invitation, :invite_expired?
      assert_equal @org_tier.actor_for_repository_invitation, T.must(repo_invitation).inviter
      assert_sponsorship_repository_created_for(tier: @org_tier, sponsor: @sponsor_of_org)
    end

    test "invites the sponsor even if the repo's invitations are currently rate limited" do
      GitHub.stubs(:repository_invitation_rate_limit).returns(0)

      assert_difference(-> { RepositoryInvitation.count }) do
        GrantSponsorsOnlyRepositoryAccessJob.perform_now(@sponsor_of_org.id, @repo.id, @org_tier.id)
      end

      repo_invitation = RepositoryInvitation.last
      assert_equal @sponsor_of_org, T.must(repo_invitation).invitee
      assert_equal @repo, T.must(repo_invitation).repository
      assert_equal "read", T.must(repo_invitation).permissions
      refute_predicate repo_invitation, :invite_expired?
      assert_equal @org_tier.actor_for_repository_invitation, T.must(repo_invitation).inviter
      assert_sponsorship_repository_created_for(tier: @org_tier, sponsor: @sponsor_of_org)
    end

    # https://github.com/github/sponsors/issues/3206
    test "creates SponsorshipRepository when there are multiple tiers that a sponsor funds that have the same repo" do
      create(:sponsorship, sponsorable: @user_sponsorable, tier: @user_tier, sponsor: @sponsor_of_org)
      GrantSponsorsOnlyRepositoryAccessJob.perform_now(@sponsor_of_org.id, @repo.id, @org_tier.id)
      GrantSponsorsOnlyRepositoryAccessJob.perform_now(@sponsor_of_org.id, @repo.id, @user_tier.id)

      assert_sponsorship_repository_created_for(tier: @org_tier, sponsor: @sponsor_of_org)
      assert_sponsorship_repository_created_for(tier: @user_tier, sponsor: @sponsor_of_org)
    end

    test "invites user sponsor with a custom tier to join a repo" do
      custom_tier = create(:sponsors_tier, :custom, sponsors_listing: @user_sponsors_listing, parent_tier: @user_tier,
        monthly_price_in_cents: @user_tier.monthly_price_in_cents + 1_00)
      sponsor = custom_tier.creator
      create(:sponsorship, sponsorable: @user_sponsorable, tier: custom_tier, sponsor: sponsor)
      assert_difference(-> { RepositoryInvitation.count }) do
        GrantSponsorsOnlyRepositoryAccessJob.perform_now(sponsor.id, @repo.id, custom_tier.id)
      end

      repo_invitation = RepositoryInvitation.last
      assert_equal sponsor, T.must(repo_invitation).invitee
      assert_equal @repo, T.must(repo_invitation).repository
      assert_equal "read", T.must(repo_invitation).permissions
      refute_predicate repo_invitation, :invite_expired?
      assert_equal @user_sponsorable, T.must(repo_invitation).inviter
      assert_sponsorship_repository_created_for(tier: custom_tier, sponsor: sponsor)
    end

    test "does not invite sponsor if repository is not valid for sponsors-only repos" do
      SponsorsTier::RepositoryValidator.any_instance.stubs(:errors).returns(["some error"])

      refute_sponsor_is_invited do
        GrantSponsorsOnlyRepositoryAccessJob.perform_now(@sponsor_of_org.id, @repo.id, @org_tier.id)
      end
    end

    test "does not invite sponsor if they are suspended" do
      @sponsor_of_user.suspend("for some reason")

      refute_sponsor_is_invited do
        GrantSponsorsOnlyRepositoryAccessJob.perform_now(@sponsor_of_user.id, @repo.id, @user_tier.id)
      end
    end

    test "does not invite sponsor if sponsor already has read access to repository" do
      @repo.add_member(@sponsor_of_user)
      assert @repo.readable_by?(@sponsor_of_user)

      refute_sponsor_is_invited do
        GrantSponsorsOnlyRepositoryAccessJob.perform_now(@sponsor_of_user.id, @repo.id, @user_tier.id)
      end
    end

    test "does not invite sponsor if repository is no longer active" do
      @repo.update_attribute(:active, nil)

      refute_sponsor_is_invited do
        GrantSponsorsOnlyRepositoryAccessJob.perform_now(@sponsor_of_user.id, @repo.id, @user_tier.id)
      end
    end

    test "does not invite sponsor if tier does not grant repository access to the sponsor" do
      SponsorsTier.any_instance.stubs(:grants_repository_access_to?).returns(false)

      refute_sponsor_is_invited do
        GrantSponsorsOnlyRepositoryAccessJob.perform_now(@sponsor_of_user.id, @repo.id, @user_tier.id)
      end
    end

    test "does not invite sponsor if repository is spammy" do
      @org.mark_as_spammy(reason: "So spammy")
      @repo.update!(user_hidden: true)
      assert @repo.reload.hide_from_user?(@sponsor_of_user)

      refute_sponsor_is_invited do
        GrantSponsorsOnlyRepositoryAccessJob.perform_now(@sponsor_of_user.id, @repo.id, @user_tier.id)
      end
    end if GitHub.spamminess_check_enabled?

    test "errors when repository invitation fails" do
      @org.update!(plan: GitHub::Plan.business_plus)
      @org.disallow_members_can_invite_outside_collaborators(actor: @org_admin, force: true)
      assert @repo.cannot_invite_outside_collaborators?(@sponsorable)

      refute_sponsor_is_invited do
        error = assert_raises(GrantSponsorsOnlyRepositoryAccessJob::FailedToInvite) do
          GrantSponsorsOnlyRepositoryAccessJob.perform_now(@sponsor_of_user.id, @repo.id, @user_tier.id)
        end

        assert_equal "Only organization owners can invite outside collaborators", error.message
      end
    end
  end

  def refute_sponsor_is_invited
    assert_no_difference(-> { RepositoryInvitation.count }) do
      assert_no_difference(-> { SponsorshipRepository.count }) do
        yield
      end
    end
  end

  def assert_sponsorship_repository_created_for(tier:, sponsor:)
    sponsorship_repository = SponsorshipRepository.for_tier(tier).for_sponsor(sponsor).first
    refute_nil sponsorship_repository
    assert_equal sponsor, T.must(sponsorship_repository).sponsor
    assert_equal tier.repository_for_sponsor(sponsor), T.must(sponsorship_repository).repository
    assert_equal tier.sponsorable, T.must(sponsorship_repository).sponsorable
    assert_equal tier, T.must(sponsorship_repository).sponsors_tier
  end
end
