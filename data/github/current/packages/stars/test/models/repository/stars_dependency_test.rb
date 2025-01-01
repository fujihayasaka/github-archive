# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryStarsDependencyTest < GitHub::TestCase
  context "#calculate_stargazer_count" do
    test "counts how many users have starred the repository" do
      repository = create(:repository)
      user1, user2 = create_pair(:user)

      assert_equal 0, repository.calculate_stargazer_count

      user1.star(repository)
      assert_equal 1, repository.calculate_stargazer_count

      user2.star(repository)
      assert_equal 2, repository.calculate_stargazer_count
    end

    test "excludes spammy user who starred the repository" do
      soon_to_be_spammer = create(:user)
      repository = create(:repository)
      soon_to_be_spammer.star(repository)

      assert_equal 1, repository.calculate_stargazer_count

      staff_user = create(:staff_admin_user)
      perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) do
        soon_to_be_spammer.mark_as_spammy(reason: "v spammy", actor: staff_user)
      end

      assert_equal 0, repository.calculate_stargazer_count
    end if GitHub.spamminess_check_enabled?
  end

  context "#update_stargazer_count!" do
    test "updates the stargazer_count field if the given value differs from the existing value" do
      repo = create(:repository, stargazer_count: 0)

      repo.update_stargazer_count!(count: 1)
      assert_equal 1, repo.reload.stargazer_count

      Repository.any_instance.expects(:update_attribute).never
      repo.update_stargazer_count!(count: 1)
      assert_equal 1, repo.reload.stargazer_count
    end
  end

  context "#stars_since" do
    test "returns cached value when set" do
      repo = create(:repository)
      cache_key = repo.stars_since_cache_key(period: :daily)
      GitHub.kv.set(cache_key, "125") # rubocop:todo GitHub/DoNotUseGlobalKv

      assert_equal repo.stars_since, 125
    end

    test "sets the cache when value is not set" do
      repo = create(:repository)
      create(:star, starrable: repo)
      cache_key = repo.stars_since_cache_key(period: :daily)

      # rubocop:todo GitHub/DoNotUseGlobalKv
      assert_changes -> { GitHub.kv.exists(cache_key).value! }, from: false, to: true do
        # rubocop:enable GitHub/DoNotUseGlobalKv
        assert_equal repo.stars_since, 1
      end
    end
  end
end
