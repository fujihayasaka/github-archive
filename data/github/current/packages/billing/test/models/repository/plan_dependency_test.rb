# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryPlanDependencyTest < GitHub::TestCase
  setup do
    @free_user = create(:user, plan: "free")
    @free_org = create(:organization, plan: "free")

    business = create(:business)
    @business_org = create(:business_plus_organization, business: business)

    @free_private_repo = create(:private_repository, owner: @free_user)
    @free_public_repo  = create(:repository, owner: @free_user)

    @business_private_repo = create(:private_repository, owner: @business_org)
    @business_public_repo  = create(:repository, owner: @business_org)
    @business_internal_repo = create(:internal_repository, owner: @business_org)

    @free_org_private_repo = create(:private_repository, owner: @free_org)
    @free_org_public_repo  = create(:repository, owner: @free_org)
  end

  context "#plan_supports?" do
    test "knows which features are supported on a free user plan" do
      refute @free_private_repo.plan_supports?(:pages)
      refute @free_private_repo.plan_supports?(:wikis)
      refute @free_private_repo.plan_supports?(:draft_prs)

      assert @free_public_repo.plan_supports?(:pages)
      assert @free_public_repo.plan_supports?(:wikis)
      assert @free_public_repo.plan_supports?(:draft_prs)
    end

    test "knows which features are supported on a free org plan" do
      refute @free_org_private_repo.plan_supports?(:wikis)
      refute @free_org_private_repo.plan_supports?(:reminders)
      refute @free_org_private_repo.plan_supports?(:draft_prs)
      refute @free_org_private_repo.plan_supports?(:team_review_requests)

      assert @free_org_public_repo.plan_supports?(:wikis)
      assert @free_org_public_repo.plan_supports?(:reminders)
      assert @free_org_public_repo.plan_supports?(:draft_prs)
      assert @free_org_public_repo.plan_supports?(:team_review_requests)
    end

    test "knows which features are supported on a business plan" do
      assert @business_private_repo.plan_supports?(:pages)
      assert @business_private_repo.plan_supports?(:wikis)
      assert @business_private_repo.plan_supports?(:draft_prs)

      assert @business_public_repo.plan_supports?(:pages)
      assert @business_public_repo.plan_supports?(:wikis)
      assert @business_public_repo.plan_supports?(:draft_prs)

      assert @business_internal_repo.plan_supports?(:pages)
      assert @business_internal_repo.plan_supports?(:wikis)
      assert @business_internal_repo.plan_supports?(:draft_prs)
    end
  end

  context "#plan_limit" do
    test "knows limits on a free plan" do
      assert_equal 10_000, @free_private_repo.plan_limit(:collaborators)
      assert_equal 10_000, @free_public_repo.plan_limit(:collaborators)
    end

    test "knows limits on a business plan" do
      assert_equal 10_000, @business_private_repo.plan_limit(:collaborators)
      assert_equal 10_000, @business_public_repo.plan_limit(:collaborators)
    end
  end

  context "#filled_seats" do
    test "returns the number of collaborators on the repo" do
      create_list(:repository_invitation, 2,
        inviter: @free_user,
        repository: @free_public_repo
      )
      assert_equal 2, @free_public_repo.filled_seats
    end
  end

  context "#seats" do
    test "returns the number of collaborator seats the repo is allowed from the owners plan" do
      assert_equal @free_user.plan_limit(:collaborators), @free_public_repo.seats
    end
  end

  context "#private_collaborator_seats" do
    test "returns the number of private collaborator seats the repo is allowed from the owners plan" do
      assert_equal @free_user.plan_limit(:collaborators, visibility: :private), @free_public_repo.private_collaborator_seats
    end
  end

  context "#available_seats" do
    test "returns the available number of collaborator seats" do
      create_list(:repository_invitation, 1,
        inviter: @free_user,
        repository: @free_public_repo
      )
      assert_equal 9999, @free_public_repo.available_seats
    end
  end

  context "at_seat_limit?" do
    test "returns false if available seats is greater than 1" do
      refute @free_private_repo.at_seat_limit?
    end
  end

  context "next_plan" do
    test "returns 'GitHub Pro' if repo is owned by personal account" do
      @free_private_repo.owner = @free_user
      assert_equal @free_private_repo.next_plan, "GitHub Pro"
    end

    test "returns 'GitHub Team' if repo is owned by organization" do
      @free_private_repo.owner = @business_org
      assert_equal @free_private_repo.next_plan, "GitHub Team"
    end

    test "doesn't fail when a free user has a large number of private repos" do
      # https://github.com/github/gitcoin/issues/2001
      user = create(:user, plan: :free)
      large_number = 10_001

      # stub because it's far too slow to actually create a large number of repos in a test
      user.stubs(:private_repo_count_for_limit_check).returns(large_number)
      user.stubs(:at_private_repo_limit?).returns(true)

      assert_nil user.next_plan
      assert_raises(GitHub::Plan::Error) { user.next_plan! }
    end
  end
end
