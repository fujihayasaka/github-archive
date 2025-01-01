# typed: true
# frozen_string_literal: true

require "test_helper"

class StarrableTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @gist = create(:gist)
  end

  setup do
    @repo = travel_to(1.hour.ago) { create(:repository) } # get an updated_at in the past
    @topic = travel_to(1.hour.ago) { create(:topic) } # get an updated_at in the past
  end

  context "#modify_stargazer_count" do
    test "increments repo stargazer_count and bumps updated_at" do
      assert_equal 0, @repo.stargazer_count
      old_updated_at = @repo.updated_at

      assert @repo.modify_stargazer_count(increment: true)

      assert_equal 1, @repo.stargazer_count
      assert_equal 1, @repo.reload.stargazer_count
      assert_operator @repo.updated_at, :>, old_updated_at
    end

    test "decrements repo stargazer_count and bumps updated_at" do
      travel_to(30.minutes.ago) { @repo.update!(stargazer_count: 1) }
      old_updated_at = @repo.updated_at

      assert @repo.modify_stargazer_count(increment: false)

      assert_equal 0, @repo.stargazer_count
      assert_equal 0, @repo.reload.stargazer_count
      assert_operator @repo.updated_at, :>, old_updated_at
    end

    test "will not decrement repo stargazer_count below 0 and does not change updated_at when count doesn't change" do
      assert_equal 0, @repo.stargazer_count
      old_updated_at = @repo.updated_at

      assert @repo.modify_stargazer_count(increment: false)

      assert_equal 0, @repo.stargazer_count
      assert_equal 0, @repo.reload.stargazer_count
      assert_equal old_updated_at, @repo.updated_at
    end

    test "increments topic stargazer_count and bumps updated_at" do
      assert_equal 0, @topic.stargazer_count
      old_updated_at = @topic.updated_at

      assert @topic.modify_stargazer_count(increment: true)

      assert_equal 1, @topic.stargazer_count
      assert_equal 1, @topic.reload.stargazer_count
      assert_operator @topic.updated_at, :>, old_updated_at
    end

    test "decrements topic stargazer_count and bumps updated_at" do
      travel_to(30.minutes.ago) { @topic.update!(stargazer_count: 1) }
      old_updated_at = @topic.updated_at

      assert @topic.modify_stargazer_count(increment: false)

      assert_equal 0, @topic.stargazer_count
      assert_equal 0, @topic.reload.stargazer_count
      assert_operator @topic.updated_at, :>, old_updated_at
    end

    test "will not decrement topic stargazer_count below 0 and does not change updated_at when count doesn't change" do
      assert_equal 0, @topic.stargazer_count
      old_updated_at = @topic.updated_at

      assert @topic.modify_stargazer_count(increment: false)

      assert_equal 0, @topic.stargazer_count
      assert_equal 0, @topic.reload.stargazer_count
      assert_equal old_updated_at, @topic.updated_at
    end

    test "no-op for gist" do
      assert_no_difference(-> { @gist.reload.stargazer_count }) do
        assert_nil @gist.modify_stargazer_count(increment: true)
      end
      assert_no_difference(-> { @gist.reload.stargazer_count }) do
        assert_nil @gist.modify_stargazer_count(increment: false)
      end
    end
  end

  context "#starred_by?" do
    test "returns false if user is nil" do
      refute @repo.starred_by?(nil)
    end

    test "raises if user is not a User" do
      assert_raises(Starrable::InvalidActorError) do
        @repo.starred_by?(@repo)
      end
    end

    test "returns true if the user has starred a repo" do
      @user.star(@repo)

      assert @repo.starred_by?(@user)
    end

    test "returns false if the user has not starred a repo" do
      refute @repo.starred_by?(@user)
    end

    test "returns true if the user has starred a gist" do
      @user.star(@gist)

      assert @gist.starred_by?(@user)
    end

    test "returns false if the user has not starred a gist" do
      refute @gist.starred_by?(@user)
    end

    test "returns true if the user has starred a topic" do
      @user.star(@topic)

      assert @topic.starred_by?(@user)
    end

    test "returns false if the user has not starred a topic" do
      refute @topic.starred_by?(@user)
    end

    test "can be prefilled to avoid N+1s" do
      other_repo = create(:repository)
      repos = [@repo, other_repo]

      assert_query_count_per_table({ stars: 1 }) do
        GitHub::PrefillAssociations.prefill_batch_method(repos, :starred_by?, @user)
      end

      assert_query_count(0) do
        repos.each do |repo|
          repo.starred_by?(@user)
        end
      end
    end
  end
end
