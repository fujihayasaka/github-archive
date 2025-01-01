# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorshipRepositoryTest < GitHub::TestCase
  context "validations" do
    test "requires repository" do
      sponsorship_repo = SponsorshipRepository.new(repository: nil)
      refute_predicate sponsorship_repo, :valid?
      assert_includes sponsorship_repo.errors[:repository], "must exist"
    end

    test "requires sponsor" do
      sponsorship_repo = SponsorshipRepository.new(sponsor: nil)
      refute_predicate sponsorship_repo, :valid?
      assert_includes sponsorship_repo.errors[:sponsor], "must exist"
    end

    test "requires sponsorable" do
      sponsorship_repo = SponsorshipRepository.new(sponsorable: nil)
      refute_predicate sponsorship_repo, :valid?
      assert_includes sponsorship_repo.errors[:sponsorable], "must exist"
    end

    test "requires tier" do
      sponsorship_repo = SponsorshipRepository.new(sponsors_tier: nil)
      refute_predicate sponsorship_repo, :valid?
      assert_includes sponsorship_repo.errors[:sponsors_tier], "must exist"
    end

    test "requires tier is for the specified sponsorable" do
      tier = create(:sponsors_tier, :approved_sponsors_listing)
      other_sponsorable = create(:user, :sponsorable)

      sponsorship_repo = SponsorshipRepository.new(sponsors_tier: tier, sponsorable: other_sponsorable)

      refute_predicate sponsorship_repo, :valid?
      assert_includes sponsorship_repo.errors[:sponsors_tier], "is not @#{other_sponsorable}'s"
    end

    test "requires a sponsorship exists for the specified sponsor using the specified tier" do
      sponsor = create(:user)
      tier = create(:sponsors_tier, :approved_sponsors_listing)
      sponsorable = tier.sponsorable

      sponsorship_repo = SponsorshipRepository.new(sponsors_tier: tier, sponsor: sponsor, sponsorable: sponsorable)

      refute_predicate sponsorship_repo, :valid?
      assert_includes sponsorship_repo.errors[:sponsor], "is not a #{tier.name} sponsor of #{sponsorable}"
    end

    test "requires the sponsorship to be active" do
      sponsor = create(:credit_card_user, :verified, plan_subscription: create(:billing_plan_subscription))
      tier = create(:sponsors_tier, :approved_sponsors_listing)
      sponsorable = tier.sponsorable
      create(:sponsorship, :inactive, tier: tier, sponsor: sponsor, sponsorable: sponsorable)

      sponsorship_repo = SponsorshipRepository.new(sponsors_tier: tier, sponsor: sponsor, sponsorable: sponsorable)

      refute_predicate sponsorship_repo, :valid?
      assert_includes sponsorship_repo.errors[:sponsor], "is not a #{tier.name} sponsor of #{sponsorable}"
    end

    test "requires a unique tier, sponsor, and repository combination" do
      sponsorship_repo1 = create(:sponsorship_repository)
      sponsorship_repo2 = SponsorshipRepository.new(sponsors_tier: sponsorship_repo1.sponsors_tier,
        sponsor: sponsorship_repo1.sponsor, repository: sponsorship_repo1.repository)

      refute_predicate sponsorship_repo2, :valid?
      assert_includes sponsorship_repo2.errors[:sponsors_tier_id], "has already been taken"
    end
  end

  context "#enqueue_revoke_access_job" do
    test "enqueues a job for removing the sponsor's repository access" do
      tier = create(:sponsors_tier, :approved_sponsors_listing, :with_repository)
      sponsor = create(:sponsorship, tier: tier, sponsorable: tier.sponsorable).sponsor
      sponsorship_repo = create(:sponsorship_repository, sponsor: sponsor, sponsors_tier: tier,
        sponsorable: tier.sponsorable, repository: tier.repository)

      assert_enqueued_with(
        job: RevokeSponsorsOnlyRepositoryAccessJob,
        args: [sponsor.id, tier.repository_id, tier.id],
      ) do
        sponsorship_repo.enqueue_revoke_access_job
      end
    end
  end

  context "sponsorship relation" do
    test "returns the sponsorship with the same tier, sponsor, and sponsorable" do
      sponsor = create(:credit_card_user, :verified, plan_subscription: create(:billing_plan_subscription))
      tier = create(:sponsors_tier, :approved_sponsors_listing)
      sponsorable = tier.sponsorable
      sponsorship = create(:sponsorship, tier: tier, sponsor: sponsor, sponsorable: sponsorable)
      sponsorship_repo = create(:sponsorship_repository, sponsor: sponsor, sponsorable: sponsorable,
        sponsors_tier: tier)

      assert_equal sponsorship, sponsorship_repo.sponsorship
    end
  end
end
