# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionLeaderboardTest < GitHub::TestCase
  context "#top_answer_counts" do
    test "it only includes users with the most selected answers, determined by the limit" do
      repo = create(:repository, has_discussions: true)
      user_with_two_answers, user_with_three_answers, user_with_one_answer = create_list(:verified_user, 3)
      create(:discussion_with_answer, repository: repo, answered_by: user_with_one_answer)
      create_pair(:discussion_with_answer, repository: repo, answered_by: user_with_two_answers)
      create_list(:discussion_with_answer, 3, repository: repo, answered_by: user_with_three_answers)

      leaderboard = DiscussionLeaderboard.new(repository: repo, viewer: repo.owner)
      answer_counts = leaderboard.top_answer_counts(limit: 2)

      assert_equal [user_with_three_answers, user_with_two_answers], answer_counts.keys
      assert_equal 3, answer_counts[user_with_three_answers]
      assert_equal 2, answer_counts[user_with_two_answers]
    end

    test "it only includes users who have recent answers" do
      repo = create(:repository, has_discussions: true)
      user_with_old_answer, user_with_new_answer = create_pair(:verified_user)
      travel_to (DiscussionLeaderboard::RECENT_TIME_PERIOD + 1.day).ago do
        create(:discussion_with_answer, repository: repo, answered_by: user_with_old_answer)
      end
      create(:discussion_with_answer, repository: repo, answered_by: user_with_new_answer)

      leaderboard = DiscussionLeaderboard.new(repository: repo, viewer: repo.owner)
      answer_counts = leaderboard.top_answer_counts(limit: 2)

      assert_equal 1, answer_counts[user_with_new_answer]
      refute_includes answer_counts, user_with_old_answer
    end

    test "it doesn't count spammy answers" do
      repo = create(:repository, has_discussions: true)
      spammer = create(:spammy_user, :verified)
      create(:discussion_with_answer, repository: repo, answered_by: spammer)

      leaderboard = DiscussionLeaderboard.new(repository: repo, viewer: repo.owner)
      answer_counts = leaderboard.top_answer_counts(limit: 1)

      refute_includes answer_counts, spammer
    end if GitHub.spamminess_check_enabled?

    test "it includes users of all repo permission levels" do
      org_admin = create(:verified_user)
      org = create(:business_plus_organization, admin: org_admin)
      org_repo = create(:repository, owner: org, has_discussions: true)

      repo_maintainer, repo_admin, repo_reader, repo_triager, repo_writer = create_list(:verified_user, 5)
      [repo_maintainer, repo_admin, repo_reader, repo_triager, repo_writer].each do |user|
        create(:discussion_with_answer, repository: org_repo, answered_by: user)
      end
      org_repo.add_member(repo_reader, action: :read)
      org_repo.add_member(repo_triager, action: :triage)
      org_repo.add_member(repo_maintainer, action: :maintain)
      org_repo.add_member(repo_writer, action: :write)
      org_repo.add_member(repo_admin, action: :admin)

      leaderboard = DiscussionLeaderboard.new(repository: org_repo, viewer: org_admin)
      answer_counts = leaderboard.top_answer_counts(limit: 5)

      assert_equal 1, answer_counts[repo_reader]
      assert_equal 1, answer_counts[repo_triager]
      assert_equal 1, answer_counts[repo_writer]
      assert_equal 1, answer_counts[repo_writer]
      assert_equal 1, answer_counts[repo_admin]
      assert_equal 1, answer_counts[repo_maintainer]
    end

    test "it doesn't include users with private profiles" do
      repo = create(:repository, has_discussions: true)
      private_profile_user = create(:user, :verified, :private_profile)
      create(:discussion_with_answer, repository: repo, answered_by: private_profile_user)

      leaderboard = DiscussionLeaderboard.new(repository: repo, viewer: repo.owner)
      answer_counts = leaderboard.top_answer_counts(limit: 1)

      refute_includes answer_counts, private_profile_user
    end

    test "it reports timing info to datadog" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      repo = create(:repository, has_discussions: true)

      leaderboard = DiscussionLeaderboard.new(repository: repo, viewer: repo.owner)
      leaderboard.top_answer_counts(limit: 1)

      assert_equal 1, GitHub.dogstats.timings("discussions.leaderboard.top_answer_counts").length
      assert_equal 1, GitHub.dogstats.timings("discussions.leaderboard.top_answer_counts.aggregation").length
    end
  end
end
