# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryHovercardDependencyTest < GitHub::TestCase
  include HydroMessageJobTestHelpers

  fixtures do
    @user = create(:user, plan: "silver")
    @anon = create(:user)

    @private_repo = create(:private_repository, owner: @user)
  end

  context "user_hovercard_parent" do
    test "returns nil if the repository is not in an organization" do
      assert_nil @private_repo.user_hovercard_parent
    end

    test "returns the organization if the repository is in one" do
      org = create(:organization)
      repo = create(:repository, owner: org)

      assert_equal org, repo.user_hovercard_parent
    end
  end

  context "contributions context" do
    test "returns a status when the user has contributed but it was more than a month ago" do
      repo = create(:private_repository, owner: @user, from_example: :pull_request_source)
      ref = repo.refs[repo.default_branch]

      perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob, HydroProfilesOnPushJob]) do
        only = [ContributionsBackfillJob]
        perform_enqueued_jobs(only: only) do
          ref.append_commit({ message: "a change", committer: @user, committed_date: 1.year.ago.iso8601 }, @user) {}
        end
      end

      assert_equal "Committed to this repository", repo.user_hovercard_context_for(@user, viewer: @user, limit: :contributions).message
    end

    test "highlights contributions in the past X" do
      repo = create(:private_repository, owner: @user, from_example: :pull_request_source)
      ref = repo.refs[repo.default_branch]

      perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob, HydroProfilesOnPushJob]) do
        only = [ContributionsBackfillJob]
        perform_enqueued_jobs(only: only) do
          ref.append_commit({ message: "a change", committer: @user }, @user) {}
        end
      end

      assert_equal "Committed to this repository in the past day", repo.user_hovercard_context_for(@user, viewer: @user, limit: :contributions).message

      # does not show the status to a non-member since this repo is private
      assert_nil repo.user_hovercard_context_for(@user, viewer: @anon, limit: :contributions)
      assert_nil repo.user_hovercard_context_for(@user, viewer: nil, limit: :contributions)
    end

    test "returns nil if the user has made no contributions" do
      context = @private_repo.user_hovercard_context_for(@user, viewer: @user, limit: :contributions)

      assert_nil context
    end

    test "returns nil if the user's profile is private for the viewer" do
      repo = create(:repository, owner: @user, from_example: :pull_request_source)
      ref = repo.refs[repo.default_branch]

      only = [ContributionsBackfillJob]
      perform_enqueued_jobs(only: only) do
        ref.append_commit({ message: "a change", committer: @user, committed_date: 1.year.ago.iso8601 }, @user) {}
      end

      @user.update!(private_profile: true)

      assert_nil repo.user_hovercard_context_for(@user, viewer: @anon, limit: :contributions)
    end
  end

  context "owner context" do
    test "returns a status if the user owns the repository" do
      context = @private_repo.user_hovercard_context_for(@user, viewer: @user, limit: :owner)

      assert_equal "Owns this repository", context.message
    end

    test "returns nil if the repository is private and viewer is not a member" do
      assert_nil @private_repo.user_hovercard_context_for(@user, viewer: @anon, limit: :owner)
      assert_nil @private_repo.user_hovercard_context_for(@user, viewer: nil, limit: :owner)
    end

    test "returns nil if the user has no relation to the repository" do
      context = @private_repo.user_hovercard_context_for(@anon, viewer: @anon, limit: :owner)

      assert_nil context
    end
  end

  context "discussion answers context" do
    test "returns status if the user has answered a discussion in this repo over a month ago" do
      repo, answerer = create_discussion_answers(2.months.ago, count: 1, nwo: "foo/bar")

      context = repo.user_hovercard_context_for(answerer, viewer: @user, limit: :discussion_answers)

      assert_equal "Answered 1 discussion in foo/bar", context.message
    end

    test "returns status if the user has answered a discussion in this repo in the past month" do
      repo, answerer = create_discussion_answers(3.weeks.ago, count: 2, nwo: "foo/bar")

      context = repo.user_hovercard_context_for(answerer, viewer: @user, limit: :discussion_answers)

      assert_equal "Answered 2 discussions in foo/bar in the past month", context.message
    end

    test "returns status if the user has answered a discussion in this repo in the past week" do
      repo, answerer = create_discussion_answers(3.days.ago, count: 3, nwo: "foo/bar")

      context = repo.user_hovercard_context_for(answerer, viewer: @user, limit: :discussion_answers)

      assert_equal "Answered 3 discussions in foo/bar in the past week", context.message
    end

    test "returns status if the user has answered a discussion in this repo in the past day" do
      repo, answerer = create_discussion_answers(3.hours.ago, count: 2, nwo: "foo/bar")

      context = repo.user_hovercard_context_for(answerer, viewer: @user, limit: :discussion_answers)

      assert_equal "Answered 2 discussions in foo/bar in the past day", context.message
    end

    test "refers to 'this repository' if the nwo is long" do
      repo, answerer = create_discussion_answers(3.hours.ago, count: 2, nwo: "reallylongnwo/reallylongnwo")

      context = repo.user_hovercard_context_for(answerer, viewer: @user, limit: :discussion_answers)

      assert_equal "Answered 2 discussions in this repository in the past day", context.message
    end

    test "returns nil if the user only answered discussions in a different repo" do
      _repo, answerer = create_discussion_answers(3.days.ago, count: 1)
      other_repo = create(:repository, has_discussions: true)

      context = other_repo.user_hovercard_context_for(answerer, viewer: @user, limit: :discussion_answers)

      assert_nil context
    end

    test "returns nil if the user's profile is private for the viewer" do
      repo, answerer = create_discussion_answers(3.hours.ago, count: 2, nwo: "foo/bar")
      answerer.update!(private_profile: true)

      assert_nil repo.user_hovercard_context_for(answerer, viewer: @user, limit: :discussion_answers)
    end

    test "returns nil if discussions are disabled" do
      repo = create(:private_repository, has_discussions: true)
      answerer = create(:verified_user)
      discussion = create(:discussion_with_answer, repository: repo, answered_by: answerer)
      repo.turn_off_discussions(actor: repo.owner, instrument: false)
      assert_nil repo.user_hovercard_context_for(answerer, viewer: answerer, limit: :discussion_answers)
    end
  end

  context "discussions started context" do
    test "returns status if the user has started a discussion in this repo over a month ago" do
      repo, creator = create_discussions(2.months.ago, count: 1, nwo: "foo/bar")

      context = repo.user_hovercard_context_for(creator, viewer: @user, limit: :discussions_started)

      assert_equal "Started 1 discussion in foo/bar", context.message
    end

    test "returns status if the user has started a discussion in this repo in the past month" do
      repo, creator = create_discussions(3.weeks.ago, count: 2, nwo: "foo/bar")

      context = repo.user_hovercard_context_for(creator, viewer: @user, limit: :discussions_started)

      assert_equal "Started 2 discussions in foo/bar in the past month", context.message
    end

    test "returns status if the user has started a discussion in this repo in the past week" do
      repo, creator = create_discussions(3.days.ago, count: 3, nwo: "foo/bar")

      context = repo.user_hovercard_context_for(creator, viewer: @user, limit: :discussions_started)

      assert_equal "Started 3 discussions in foo/bar in the past week", context.message
    end

    test "returns status if the user has started a discussion in this repo in the past day" do
      repo, creator = create_discussions(3.hours.ago, count: 2, nwo: "foo/bar")

      context = repo.user_hovercard_context_for(creator, viewer: @user, limit: :discussions_started)

      assert_equal "Started 2 discussions in foo/bar in the past day", context.message
    end

    test "refers to 'this repository' if the nwo is long" do
      repo, creator = create_discussions(3.hours.ago, count: 2, nwo: "reallylongnwo/reallylongnwo")

      context = repo.user_hovercard_context_for(creator, viewer: @user, limit: :discussions_started)

      assert_equal "Started 2 discussions in this repository in the past day", context.message
    end

    test "returns nil if the user only started discussions in a different repo" do
      _repo, creator = create_discussions(3.days.ago, count: 1)
      other_repo = create(:repository, has_discussions: true)

      context = other_repo.user_hovercard_context_for(creator, viewer: @user, limit: :discussions_started)

      assert_nil context
    end

    test "returns nil if the user's profile is private for the viewer" do
      repo, creator = create_discussions(3.hours.ago, count: 2, nwo: "foo/bar")
      creator.update!(private_profile: true)

      assert_nil repo.user_hovercard_context_for(creator, viewer: @user, limit: :discussions_started)
    end

    test "returns nil if  discussions are disabled" do
      repo = create(:private_repository, has_discussions: true)
      creator = create(:verified_user)
      discussion = create(:discussion, repository: repo, user: creator)
      repo.turn_off_discussions(actor: repo.owner, instrument: false)
      assert_nil repo.user_hovercard_context_for(creator, viewer: creator, limit: :discussion_answers)
    end
  end

  # Returns [Repository, User], where the User is the one whose answers were chosen in this repo
  def create_discussion_answers(created_at, count:, nwo: "foo/bar")
    owner_login, repo_name = nwo.split("/")
    travel_to created_at do
      answerer = create(:verified_user, login: owner_login)
      repo = create(:repository, name: repo_name, has_discussions: true, owner: answerer)
      discussion = create_list(:discussion_with_answer, count, repository: repo, answered_by: answerer)
      [repo, answerer]
    end
  end

  # Returns [Repository, User], where the User is the one who started the discussions
  def create_discussions(created_at, count:, nwo: "foo/bar")
    owner_login, repo_name = nwo.split("/")
    travel_to created_at do
      creator = create(:verified_user, login: owner_login)
      repo = create(:repository, name: repo_name, has_discussions: true, owner: creator)
      discussion = create_list(:discussion, count, repository: repo, user: creator)
      [repo, creator]
    end
  end
end
