# typed: true
# frozen_string_literal: true

require "test_helper"

class ContributionInsightsTest < GitHub::TestCase
  include MetricsHelper
  include HydroMessageJobTestHelpers

  fixtures do
    @user1  = create(:user, login: "user1", email: "user1@github.com")
    @user2  = create(:user, login: "user2", email: "user2@github.com")
    @user3  = create(:user, login: "user3", email: "user3@github.com")
    @repo = create :repository, from_example: :empty


    Timecop.freeze(Time.new(2023, 1, 2, 3, 4, 5).utc) do
      # make a bunch of commits, each 1 hour apart
      commit(@user1, 1)
      commit(@user2, 2)
      commit(@user3, 3)
      Timecop.travel(18.hours)
      commit(@user1, 4)
      commit(@user2, 5)
      commit(@user3, 6)
      Timecop.travel(9.hours)
      commit(@user1, 7)
      commit(@user2, 8)
      commit(@user3, 9)

      example_repo_snapshot
    end
  end

  setup do
    example_repo_restore
    # freeze time a few days later
    @time = Time.new(2023, 1, 10, 0, 0, 0).utc
  end

  def commit(pusher, count)
    Timecop.travel(1.hour)
    perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob, HydroProfilesOnPushJob]) do
      perform_enqueued_jobs(only: [ContributionsBackfillJob, ContributionsTrackPushJob]) do
        count.times do
          before = @repo.ref_to_sha("master") || GitHub::NULL_OID
          ref = Git::Ref.new(@repo, "refs/heads/master", before)

          metadata = { message: "a commit", committer: pusher, author: pusher }

          ref.append_commit(metadata, pusher) do |files|
            files.add("file.txt", SecureRandom.hex(10).to_s)
          end
        end
      end
    end
  end

  def insights
    GitHub::RepoGraph::ContributionInsights.new(@repo)
  end

  test "code frequency should be zeros" do
    Timecop.freeze(@time) do
      data = insights.fetch_code_frequency_data

      expected_data =
      {
        "RepoGraphs_Additions" => { "1673308800" => 0, "1673222400" => 0, "1673136000" => 0, "1673049600" => 0, "1672963200" => 0, "1672876800" => 0, "1672790400" => 0, "1672704000" => 0 },
        "RepoGraphs_Deletions" => { "1673308800" => 0, "1673222400" => 0, "1673136000" => 0, "1673049600" => 0, "1672963200" => 0, "1672876800" => 0, "1672790400" => 0, "1672704000" => 0 }
      }

      assert_same_hash expected_data, data
    end
  end

  test "contributors data" do
    Timecop.freeze(@time) do
      data = insights.fetch_contributors_data

      expected_data =
      {
        "RepoGraphs_Commits" =>
        {
          "user3@github.com" => { 1672646400 => 3, 1672732800 => 15 },
          "user2@github.com" => { 1672646400 => 2, 1672732800 => 13 },
          "user1@github.com" => { 1672646400 => 1, 1672732800 => 11 }
        },
        "RepoGraphs_Additions" =>
        {
          "user3@github.com" => { 1672646400 => 0, 1672732800 => 0 },
          "user2@github.com" => { 1672646400 => 0, 1672732800 => 0 },
          "user1@github.com" => { 1672646400 => 0, 1672732800 => 0 }
        },
        "RepoGraphs_Deletions" =>
        {
          "user3@github.com" => { 1672646400 => 0, 1672732800 => 0 },
          "user2@github.com" => { 1672646400 => 0, 1672732800 => 0 },
          "user1@github.com" => { 1672646400 => 0, 1672732800 => 0 }
        }
      }

      assert_same_hash expected_data, data
    end
  end

  test "commit activity data" do
    Timecop.freeze(@time) do
      data = insights.fetch_commit_activity_data

      expected_data =
      {
        "RepoGraphs_Commits" => [[1672646400, 6], [1672732800, 39]]
      }

      assert_same_hash expected_data, data
    end
  end
end
