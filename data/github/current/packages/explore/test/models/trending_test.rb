# typed: true
# frozen_string_literal: true

require "test_helper"

class TrendingTest < GitHub::TestCase
  fixtures do
    ruby_id = create(:language_name, name: "Ruby", linguist_id: 326).id
    python_id = create(:language_name, name: "Python", linguist_id: 303).id

    @period = "daily"

    @user = create(:user)
    @stan = create(:user, login: "stan")
    @francine = create(:user, login: "francine")
    @steve = create(:user, login: "steve")
    @haliey = create(:user, login: "haliey")
    @roger = create(:user, login: "roger")
    @klaus = create(:user, login: "klaus")

    @famous_repo = create(:repository, owner: @roger, name: "famous_repo", primary_language_name_id: ruby_id, created_at: 1.week.ago)
    @famous_repo.update!(stargazer_count: 100)
    @famous_repo.update!(pushed_at: 1.minute.ago)

    @lame_repo = create(:repository, owner: @steve, name: "lame_repo", primary_language_name_id: python_id, created_at: 1.week.ago)
    @lame_repo.update!(stargazer_count: 2)
    @lame_repo.update!(pushed_at: 1.minute.ago)

    @old_repo = create(:repository, owner: @roger, name: "old_repo", created_at: 1.year.ago)
    @old_repo.update!(stargazer_count: 100)
    @old_repo.update!(pushed_at: 1.month.ago)
  end

  setup do
    reset_cache
  end

  def create_profane_name(postfix = "")
    "thef" + "uck#{postfix}" # rubocop:disable Style/StringConcatenation
  end

  test "limit works on list" do
    @francine.follow @stan
    @steve.follow @stan
    @francine.follow @roger
    @steve.follow @roger

    assert_equal 2, Trending.users({ period: @period }).count
    assert_equal 1, Trending.users({ period: @period, limit: 1 }).count
  end

  context "trending users" do
    test "deleted users don't return nils" do
      Trending.any_instance.stubs(:fetch_trenders).returns([[@stan.id, {}]])
      @stan.destroy
      users = Trending.users(period: @period)

      assert_empty users
    end

    test "we get user back with at least 2 follows" do
      @francine.follow @stan
      @steve.follow @stan
      @francine.follow @roger

      first_trending_user, _ = Trending.users(period: @period).first

      assert_equal @stan, first_trending_user
    end

    test "users with the avg stars per period, get in trending" do
      @stan.star @famous_repo
      @francine.star @famous_repo
      @haliey.star @famous_repo
      @steve.star @famous_repo
      @klaus.star @famous_repo

      first_trending_user, score = Trending.users({ period: @period, skip_min: true }).first

      assert_equal @famous_repo.owner, first_trending_user
    end

    test "users with ruby get selected" do
      @stan.star @famous_repo
      @francine.star @famous_repo
      @haliey.star @famous_repo
      @steve.star @famous_repo
      @klaus.star @famous_repo

      @stan.star @lame_repo
      @francine.star @lame_repo
      @haliey.star @lame_repo
      @steve.star @lame_repo
      @klaus.star @lame_repo

      assert_equal 1, Trending.users({ period: @period, language: "ruby", skip_min: true }).count
    end

    test "users with unknown repos get selected" do
      @stan.star @old_repo
      @francine.star @old_repo
      @haliey.star @old_repo
      @steve.star @old_repo
      @klaus.star @old_repo

      @stan.star @lame_repo
      @francine.star @lame_repo
      @haliey.star @lame_repo
      @steve.star @lame_repo
      @klaus.star @lame_repo

      assert_equal 1, Trending.users({ period: @period, language: "unknown", skip_min: true }).count
    end

    test "users with follows and stars are first" do
      @stan.star @famous_repo
      @francine.star @famous_repo
      @haliey.star @famous_repo
      @steve.star @famous_repo
      @klaus.star @famous_repo

      @stan.star @lame_repo
      @francine.star @lame_repo
      @haliey.star @lame_repo
      @steve.star @lame_repo
      @klaus.star @lame_repo

      @francine.follow @roger
      @steve.follow @roger

      Timecop.freeze(1.hour.ago) do
        assert_equal 2, Trending.users({ period: @period, skip_min: true }).count

        first_trending_user, score = Trending.users({ period: @period, skip_min: true }).first
        second_trending_user, score = Trending.users({ period: @period, skip_min: true }).last

        assert_equal @roger, first_trending_user
        assert_equal @steve, second_trending_user
      end
    end

    test "users with private profiles are not included" do
      @francine.follow @stan
      @steve.follow @stan
      @francine.follow @roger
      @steve.follow @roger

      @stan.update!(private_profile: true)

      trending_users = Trending.users(period: @period).map(&:first)

      refute_includes trending_users, @stan
    end
  end

  context "#trending_score_sql" do
    test "returns a trending score sql string for the given time period" do
      Timecop.freeze("2018-07-01") do
        daily_trending = Trending.new(period: "daily")
        score_sql = Arel.sql(daily_trending.send(:trending_score_sql, max: TrendingScorer::STAR_MAX, min: TrendingScorer::STAR_MIN, column: "created_at"))

        star = create(:star, created_at: DateTime.now)
        assert_in_delta 5.0, Star.where(id: star).pick(score_sql), 0.1

        star = create(:star, created_at: 1.hour.ago)
        assert_in_delta 4.875, Star.where(id: star).pick(score_sql), 0.1

        star = create(:star, created_at: 2.hours.ago)
        assert_in_delta 4.75, Star.where(id: star).pick(score_sql), 0.1

        star = create(:star, created_at: 3.hours.ago)
        assert_in_delta 4.625, Star.where(id: star).pick(score_sql), 0.1

        star = create(:star, created_at: 4.hours.ago)
        assert_in_delta 4.5, Star.where(id: star).pick(score_sql), 0.1

        weekly_trending = Trending.new(period: "weekly")
        score_sql = Arel.sql(weekly_trending.send(:trending_score_sql, max: TrendingScorer::STAR_MAX, min: TrendingScorer::STAR_MIN, column: "created_at"))

        star = create(:star, created_at: DateTime.now)
        assert_in_delta 5.0, Star.where(id: star).pick(score_sql), 0.1

        star = create(:star, created_at: 1.day.ago)
        assert_in_delta 4.57, Star.where(id: star).pick(score_sql), 0.1

        star = create(:star, created_at: 2.days.ago)
        assert_in_delta 4.14, Star.where(id: star).pick(score_sql), 0.1

        star = create(:star, created_at: 3.days.ago)
        assert_in_delta 3.71, Star.where(id: star).pick(score_sql), 0.1

        star = create(:star, created_at: 4.days.ago)
        assert_in_delta 3.28, Star.where(id: star).pick(score_sql), 0.1

        monthly_trending = Trending.new(period: "monthly")
        score_sql = Arel.sql(monthly_trending.send(:trending_score_sql, max: TrendingScorer::STAR_MAX, min: TrendingScorer::STAR_MIN, column: "created_at"))

        star = create(:star, created_at: DateTime.now)
        assert_in_delta 5.0, Star.where(id: star).pick(score_sql), 0.1

        star = create(:star, created_at: 1.day.ago)
        assert_in_delta 4.9, Star.where(id: star).pick(score_sql), 0.1

        star = create(:star, created_at: 2.days.ago)
        assert_in_delta 4.8, Star.where(id: star).pick(score_sql), 0.1

        star = create(:star, created_at: 3.days.ago)
        assert_in_delta 4.7, Star.where(id: star).pick(score_sql), 0.1

        star = create(:star, created_at: 4.days.ago)
        assert_in_delta 4.6, Star.where(id: star).pick(score_sql), 0.1
      end
    end
  end

  context ".repo_id" do
    test "fetches cached trending repos" do
      parse_period = "daily"
      options = { period: parse_period }
      cache_key = "trending:repos:query:#{parse_period}"
      trenders = { @famous_repo.id => {
        forks: { total: 4, score: 14.26964546783232 },
        languages: [7],
        stars: { total: 5, score: 23.26964546783232 } },
      }

      GitHub.cache.expects(:fetch).with(cache_key).returns(trenders)
      Trending.repo_ids(options)
    end

    test "repos with forks and stars show up in trending repos" do
      create(:fork_repository, forker: @stan, fork_repo: @famous_repo)
      @stan.star @famous_repo
      create(:fork_repository, forker: @haliey, fork_repo: @famous_repo)
      @haliey.star @famous_repo
      create(:fork_repository, forker: @francine, fork_repo: @famous_repo)
      @francine.star @famous_repo
      @roger.star @famous_repo
      create(:fork_repository, forker: @steve, fork_repo: @famous_repo)
      @steve.star @famous_repo

      first_trending_repo_id, score = Trending.repo_ids({ period: @period, skip_min: true }).first

      assert_equal 5, Star.where(starrable_id: @famous_repo.id).count
      assert_equal @famous_repo.id, first_trending_repo_id
    end

    test "repos with forks but no stars don't show up in trending repos" do
      create(:fork_repository, forker: @stan, fork_repo: @famous_repo)

      # to skip minimum things
      @famous_repo.update!(public_fork_count: 50, stargazer_count: 0)

      repo_ids = Trending.repo_ids({ period: @period, limit: 1 }).map { |repo, _score| repo }

      refute repo_ids.include?(@famous_repo.id)
    end

    test "repos forks query language filter works" do
      create(:fork_repository, forker: @stan, fork_repo: @famous_repo)
      @stan.star @famous_repo

      create(:fork_repository, forker: @stan, fork_repo: @lame_repo)
      @stan.star @lame_repo

      @famous_repo.update!(public_fork_count: 100, stargazer_count: 100)
      @lame_repo.update!(public_fork_count: 100, stargazer_count: 100)

      first_trending_repo_id, score = Trending.repo_ids({ period: @period, language: "ruby" }).first

      assert_equal @famous_repo.id, first_trending_repo_id
    end

    test "unknown repos get selected from forks" do
      create(:fork_repository, forker: @stan, fork_repo: @old_repo)
      create(:fork_repository, forker: @stan, fork_repo: @lame_repo)

      @old_repo.update!(public_fork_count: 100)
      @old_repo.update!(pushed_at: 1.minute.ago)
      @lame_repo.update!(public_fork_count: 100)

      assert_equal 1, Trending.repo_ids({ period: @period, language: "unknown" }).count
    end

    test "deleted repos don't return nils" do
      Trending.any_instance.stubs(:repo_ids).returns([[@famous_repo.id, 1]])
      @famous_repo.destroy
      repos = Trending.repos(ttl: 2.hours, options: { period: @period })
      assert_equal 0, repos.length
    end

    test "if a viewer has owner blocked its not returned" do
      Trending.any_instance.stubs(:repo_ids).returns([[@famous_repo.id, 1]])
      @user.block(@famous_repo.owner)
      assert_equal 0, Trending.repos(viewer: @user, ttl: 2.hours, options: { period: @period }).length
    end

    test "if no viewer the original set is returned" do
      Trending.any_instance.stubs(:repo_ids).returns([[@famous_repo.id, 1]])
      @user.block(@famous_repo.owner)
      assert_equal 1, Trending.repos(ttl: 2.hours, options: { period: @period }).length
    end

    test "repos with inappropriate names do not appear in trending repos" do
      naughty_repo = create(:repository, owner: @roger, name: create_profane_name, created_at: 1.hour.ago)
      naughty_repo.update!(stargazer_count: 1000)
      naughty_repo.update!(pushed_at: 1.minute.ago)

      trending_repo_ids = Trending.repo_ids({ period: @period }).map(&:first)

      refute trending_repo_ids.include?(naughty_repo.id), "inappropriate name should be filtered out"
    end

    test "repos marked with hide_from_discovery should be filtered out" do
      naughty_repo = create(:repository, owner: @roger, name: "eeeeeeeeeeeeeeeee", created_at: 1.hour.ago)
      naughty_repo.update!(stargazer_count: 1000)
      naughty_repo.update!(pushed_at: 1.minute.ago)
      naughty_repo.set_network_privilege(:hide_from_discovery, true)

      trending_repo_ids = Trending.repo_ids({ period: @period }).map(&:first)

      refute trending_repo_ids.include?(naughty_repo.id), "hide_from_discovery repos should be filted out"
    end

    test "trending repos backfill to 25 when inappropriate names are filtered" do
      25.times do |i|
        nice_repo = create(:repository, owner: @roger, name: "thefreak#{i}", created_at: 1.hour.ago)
        nice_repo.update!(stargazer_count: i)
        nice_repo.update!(pushed_at: 1.minute.ago)
      end

      25.times do |i|
        naughty_repo = create(:repository, owner: @roger, name: create_profane_name(i), created_at: 1.hour.ago)
        naughty_repo.update!(stargazer_count: 1000 + i)
        naughty_repo.update!(pushed_at: 1.minute.ago)
      end

      trending_repo_ids = Trending.repo_ids({ period: @period }).map(&:first)

      assert_equal 25, trending_repo_ids.size
    end

    test "trending repos contains < 25 if there are no repos to backfill with" do
      trending_repo_ids = Trending.repo_ids({ period: @period }).map(&:first)

      assert trending_repo_ids.size < 25
    end
  end
end
