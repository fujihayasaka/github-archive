# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryUserRankedDependencyTest < GitHub::TestCase
  fixtures do
    @user = create(:user, plan: "medium")

    @public_repo = create(:repository, owner: @user)
    @private_repo = create(:private_repository, owner: @user)
  end

  test "returns nothing if the user has not made any contributions" do
    assert_empty Repository.compute_ranked_ids(user: @user)
  end

  test "returns array of repository ids ordered by the number of contributions made by user" do
    create(:issue, user: @user, repository: @public_repo)
    create(:issue, user: @user, repository: @public_repo)
    create(:issue, user: @user, repository: @private_repo)

    assert_equal [@public_repo.id, @private_repo.id], Repository.compute_ranked_ids(user: @user)
  end

  test "does not include ids of repositories that the user has not contributed to" do
    additional_repo = create(:repository)
    create(:issue, user: @user, repository: @public_repo)

    assert_includes Repository.compute_ranked_ids(user: @user), @public_repo.id
    refute_includes Repository.compute_ranked_ids(user: @user), additional_repo.id
  end

  context ".eager_ranked_for" do
    test "returns array of repositories ordered by the number of contributions made by user" do
      create(:issue, user: @user, repository: @public_repo)
      create(:issue, user: @user, repository: @public_repo)
      create(:issue, user: @user, repository: @private_repo)

      assert_equal [@public_repo, @private_repo], Repository.eager_ranked_for(@user)
    end

    test "only counts contributions after `since`" do
      Timecop.freeze(2.years.ago) { create(:issue, user: @user, repository: @public_repo) }
      create(:issue, user: @user, repository: @public_repo)
      create(:issue, user: @user, repository: @private_repo)
      create(:issue, user: @user, repository: @private_repo)

      assert_equal [@private_repo, @public_repo], Repository.eager_ranked_for(@user, since: 3.months.ago)
    end

    test "caches results by month and year" do
      with_cache_enabled do
        Timecop.freeze("2020-08-24") do
          create(:issue, user: @user, repository: @public_repo)
          create(:issue, user: @user, repository: @public_repo)
          create(:issue, user: @user, repository: @private_repo)

          assert_equal [@public_repo, @private_repo], Repository.eager_ranked_for(@user, since: 2.days.ago)

          create(:issue, user: @user, repository: @private_repo)
          create(:issue, user: @user, repository: @private_repo)

          # Reset ivar to allow recalculation on cache miss
          @user.instance_variable_set(:@ranked_contributed_repositories, nil)

          assert_equal [@public_repo, @private_repo], Repository.eager_ranked_for(@user, since: 5.days.ago)
          assert_equal [@private_repo, @public_repo], Repository.eager_ranked_for(@user, since: 1.year.ago)
        end
      end
    end
  end
end
