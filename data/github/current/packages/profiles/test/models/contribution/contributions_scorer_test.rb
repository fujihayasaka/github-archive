# typed: true
# frozen_string_literal: true

require "test_helper"

class ContributionScorerTest < GitHub::TestCase
  fixtures do
    @user   = create :user, login: "fanboy"
    @repo   = create :repository,  name: "popular"
    @repo2   = create :repository, name: "ohnorepo"

    @commit_range = (Contribution::Scorer::COMMIT_MIN..Contribution::Scorer::COMMIT_MAX)

    @issue1 = @user.issues.create! \
      repository: @repo,
      contributed_at: Time.zone.now,
      title: "Mo Money, Mo Problems"

    @issue2 = @user.issues.create! \
      repository: @repo,
      title: "Don't oblidge the police",
      created_at: 1.day.ago,
      contributed_at: 1.day.ago
  end

  setup do
    @scorer = Contribution::Scorer.new(Time.zone.today - 5.days)
    @unweighted_scorer = Contribution::Scorer.new(Time.zone.today - 5.days, weighted: false)
    @issue1_contribution = Contribution::CreatedIssue.new(user: @user, subject: @issue1)
    @issue2_contribution = Contribution::CreatedIssue.new(user: @user, subject: @issue2)
  end

  test "domain is set" do
    scorer = Contribution::Scorer.new(Time.zone.today - 10.days)
    scorer2 = Contribution::Scorer.new(Time.zone.today - 10.days, Time.zone.today - 5.days)

    assert_equal [0.0, 10.0], scorer.domain
    assert_equal [5.0, 10.0], scorer2.domain
  end

  test "scores contribution between min and max" do
    commit = create(:commit_contribution,
      repository: @repo,
      user: @user,
      commit_count: 1,
      committed_date: Time.zone.today - 2.days,
    )
    commit_contribution = Contribution::CreatedCommit.new(user: @user, subject: commit)

    assert @commit_range.include?(@scorer.score_commit(commit_contribution))
  end

  test "contribution happened yesterday is lower than the max rank" do
    commit = create(:commit_contribution,
      repository: @repo,
      user: @user,
      commit_count: 1,
      committed_date: Time.zone.today - 1.day,
    )
    commit_contribution = Contribution::CreatedCommit.new(user: @user, subject: commit)

    assert @scorer.score_commit(commit_contribution) < Contribution::Scorer::COMMIT_MAX
  end

  test "clamps contribution score to min or max when out of range" do
    old = create(:commit_contribution,
      repository: @repo,
      user: @user,
      commit_count: 1,
      committed_date: Time.zone.today - 100.days,
    )
    old_contribution = Contribution::CreatedCommit.new(user: @user, subject: old)

    future = create(:commit_contribution,
      repository: @repo,
      user: @user,
      commit_count: 1,
      committed_date: Time.zone.today + 100.days,
    )
    future_contribution = Contribution::CreatedCommit.new(user: @user, subject: future)

    assert_equal 2.0, @scorer.score_commit(future_contribution)
    assert_equal 1.0, @scorer.score_commit(old_contribution)
  end

  context "ranking contributions when weighted is true" do

    test "commit is worth more than an issue created on the same day" do
      commit = create(:commit_contribution,
        repository: @repo,
        user: @user,
        commit_count: 1,
        committed_date: Time.zone.today,
      )
      commit_contribution = Contribution::CreatedCommit.new(user: @user, subject: commit)

      issue = @user.issues.create! \
        repository: @repo,
        contributed_at: Time.zone.now,
        title: "Mo Money, Mo Problems"
      issue_contribution = Contribution::CreatedIssue.new(user: @user, subject: issue)

      assert @scorer.score_commit(commit_contribution) > @scorer.score_issue(issue_contribution)
    end

    test "a later contribution is worth more than a earlier contribution" do
      assert @scorer.score_issue(@issue1_contribution) > @scorer.score_issue(@issue2_contribution)
    end

    test "two commits today in one contribution is worth more than two commit contributions" do
      # Repo 1 - 1 Commit contribution with 2 commits happening today
      commit_many = create(:commit_contribution,
        repository: @repo,
        user: @user,
        commit_count: 2,
        committed_date: Time.zone.today,
      )
      commit_many_contribution = Contribution::CreatedCommit.new(user: @user, subject: commit_many)

      # Repo 2: Two commit contributions, one today, one yesterday
      commit_one = create(:commit_contribution,
        repository: @repo2,
        user: @user,
        commit_count: 1,
        committed_date: Time.zone.today,
      )
      commit_one_contribution = Contribution::CreatedCommit.new(user: @user, subject: commit_one)

      commit_two = create(:commit_contribution,
        repository: @repo2,
        user: @user,
        commit_count: 1,
        committed_date: Time.zone.today - 1.day,
      )
      commit_two_contribution = Contribution::CreatedCommit.new(user: @user, subject: commit_two)

      assert @scorer.score_commit(commit_many_contribution) > @scorer.score_commits([commit_one_contribution, commit_two_contribution])
    end
  end

  context "ranking contributions when weighted is false" do
    test "commit is worth same as an issue created on the same day" do
      commit = create(:commit_contribution,
        repository: @repo,
        user: @user,
        commit_count: 1,
        committed_date: Time.zone.today,
      )
      commit_contribution = Contribution::CreatedCommit.new(user: @user, subject: commit)

      issue = @user.issues.create! \
        repository: @repo,
        contributed_at: Time.zone.now,
        title: "Mo Money, Mo Problems"
      issue_contribution = Contribution::CreatedIssue.new(user: @user, subject: issue)

      assert @unweighted_scorer.score_commit(commit_contribution) == @unweighted_scorer.score_issue(issue_contribution)
    end

    test "a later contribution is worth the same as an earlier contribution" do
      assert @unweighted_scorer.score_issue(@issue1_contribution) == @unweighted_scorer.score_issue(@issue2_contribution)
    end

    test "two commits today in one contribution is worth the same as two commit contributions" do
      # Repo 1 - 1 Commit contribution with 2 commits happening today
      commit_many = create(:commit_contribution,
        repository: @repo,
        user: @user,
        commit_count: 2,
        committed_date: Time.zone.today,
      )
      commit_many_contribution = Contribution::CreatedCommit.new(user: @user, subject: commit_many)

      # Repo 2: Two commit contributions, one today, one yesterday
      commit_one = create(:commit_contribution,
        repository: @repo2,
        user: @user,
        commit_count: 1,
        committed_date: Time.zone.today,
      )
      commit_one_contribution = Contribution::CreatedCommit.new(user: @user, subject: commit_one)

      commit_two = create(:commit_contribution,
        repository: @repo2,
        user: @user,
        commit_count: 1,
        committed_date: Time.zone.today - 1.day,
      )
      commit_two_contribution = Contribution::CreatedCommit.new(user: @user, subject: commit_two)

      assert @unweighted_scorer.score_commit(commit_many_contribution) == @unweighted_scorer.score_commits([commit_one_contribution, commit_two_contribution])
    end
  end
end
