# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class RevokeSponsorsOnlyRepositoryAccessJobTest < GitHub::TestCase
  fixtures do
    @org_admin = create(:user)
    @org = create(:organization, :sponsorable, admin: @org_admin)
    @repo = create(:private_repository, owner: @org)

    @user_sponsorable = create(:user, :sponsorable)
    @repo.add_member(@user_sponsorable, @org_admin, action: :admin)

    @user_tier = create(:sponsors_tier, :published, sponsors_listing: @user_sponsorable.sponsors_listing,
      repository: @repo)
    @org_tier = create(:sponsors_tier, :published, sponsors_listing: @org.sponsors_listing, repository: @repo)

    @sponsor_of_user = create(:sponsorship, sponsorable: @user_sponsorable, tier: @user_tier).sponsor
    @sponsor_of_org = create(:sponsorship, sponsorable: @org, tier: @org_tier).sponsor

    @user_sponsorship_repo = create(:sponsorship_repository, sponsor: @sponsor_of_user,
      sponsorable: @user_sponsorable, sponsors_tier: @user_tier, repository: @repo)
    @org_sponsorship_repo = create(:sponsorship_repository, sponsor: @sponsor_of_org,
      sponsorable: @org, sponsors_tier: @org_tier, repository: @repo)

    @user_repo_invitation = create(:repository_invitation, repository: @repo, invitee: @sponsor_of_user,
      inviter: @user_sponsorable)
    @org_repo_invitation = create(:repository_invitation, repository: @repo, invitee: @sponsor_of_org, inviter: @org)
  end

  setup do
    skip unless GitHub.sponsors_enabled?
  end

  context "#perform" do
    test "deletes existing repo invitation and SponsorshipRepository for sponsor of a user sponsorable" do
      assert_difference(-> { SponsorshipRepository.count }, -1) do
        assert_difference(-> { RepositoryInvitation.count }, -1) do
          RevokeSponsorsOnlyRepositoryAccessJob.perform_now(@sponsor_of_user.id, @repo.id, @user_tier.id)
        end
      end

      refute RepositoryInvitation.exists?(@user_repo_invitation.id)
      refute SponsorshipRepository.exists?(@user_sponsorship_repo.id)
    end

    test "deletes existing repo invitation and SponsorshipRepository for sponsor of an org sponsorable" do
      assert_difference(-> { SponsorshipRepository.count }, -1) do
        assert_difference(-> { RepositoryInvitation.count }, -1) do
          RevokeSponsorsOnlyRepositoryAccessJob.perform_now(@sponsor_of_org.id, @repo.id, @org_tier.id)
        end
      end

      refute RepositoryInvitation.exists?(@org_repo_invitation.id)
      refute SponsorshipRepository.exists?(@org_sponsorship_repo.id)
    end

    test "removes sponsor's repo membership when a user was sponsored" do
      assert @user_repo_invitation.accept!
      assert @repo.readable_by?(@sponsor_of_user)

      RevokeSponsorsOnlyRepositoryAccessJob.perform_now(@sponsor_of_user.id, @repo.id, @user_tier.id)

      refute @repo.readable_by?(@sponsor_of_user)
    end

    test "removes sponsor's repo membership when an organization was sponsored" do
      assert @org_repo_invitation.accept!
      assert @repo.readable_by?(@sponsor_of_org)

      RevokeSponsorsOnlyRepositoryAccessJob.perform_now(@sponsor_of_org.id, @repo.id, @org_tier.id)

      refute @repo.readable_by?(@sponsor_of_org)
    end

    test "does not error if repository doesn't exist" do
      @repo.delete

      assert_no_difference(-> { RepositoryInvitation.count }) do
        RevokeSponsorsOnlyRepositoryAccessJob.perform_now(@sponsor_of_user.id, @repo.id, @user_tier.id)
      end
    end

    test "does not error if sponsor doesn't exist" do
      @sponsor_of_user.delete

      assert_no_difference(-> { RepositoryInvitation.count }) do
        RevokeSponsorsOnlyRepositoryAccessJob.perform_now(@sponsor_of_user.id, @repo.id, @user_tier.id)
      end
    end

    test "does not error if tier doesn't exist" do
      @user_tier.delete

      assert_no_difference(-> { RepositoryInvitation.count }) do
        RevokeSponsorsOnlyRepositoryAccessJob.perform_now(@sponsor_of_user.id, @repo.id, @user_tier.id)
      end
    end

    test "does not delete invitation if no SponsorshipRepository record exists" do
      @user_sponsorship_repo.delete

      assert_no_difference(-> { RepositoryInvitation.count }) do
        RevokeSponsorsOnlyRepositoryAccessJob.perform_now(@sponsor_of_user.id, @repo.id, @user_tier.id)
      end
    end

    test "does not delete SponsorshipRepository if invitation fails to cancel" do
      RepositoryInvitation.any_instance.stubs(:destroy).returns(false)

      assert_no_difference(-> { SponsorshipRepository.count }) do
        RevokeSponsorsOnlyRepositoryAccessJob.perform_now(@sponsor_of_user.id, @repo.id, @user_tier.id)
      end

      assert SponsorshipRepository.exists?(@user_sponsorship_repo.id)
    end

    # https://github.com/github/sponsors/issues/3206
    test "deletes SponsorshipRepository but keeps membership if sponsor should have access from different tier" do
      assert @user_repo_invitation.accept!
      assert @repo.readable_by?(@sponsor_of_user)
      create(:sponsorship_repository, sponsor: @sponsor_of_user,
      sponsorable: @org, sponsors_tier: @org_tier, repository: @repo)

      assert_difference(-> { SponsorshipRepository.count }, -1) do
        RevokeSponsorsOnlyRepositoryAccessJob.perform_now(@sponsor_of_user.id, @repo.id, @user_tier.id)
      end

      assert @repo.readable_by?(@sponsor_of_user)
    end
  end
end
