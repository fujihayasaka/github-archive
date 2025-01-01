# typed: true
# frozen_string_literal: true

require "test_helper"

class ProfilePinnerTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @profile = create(:profile, user: @user)
  end

  setup do
    @pinner = ProfilePinner.new(user: @user, viewer: @user)
  end

  context "#async_pinnable_items" do
    test "includes gists when viewer is in feature" do
      user = create(:user)
      gist = create(:gist, user: user)
      viewer = create(:user)
      pinner = ProfilePinner.new(user: user, viewer: viewer)

      assert_includes pinner.async_pinnable_items.sync, gist
    end

    test "omits gists when types does not include Gist" do
      user = create(:user)
      gist = create(:gist, user: user)
      viewer = create(:user)
      pinner = ProfilePinner.new(user: user, viewer: viewer)

      refute_includes pinner.async_pinnable_items(types: ["Repository"]).sync, gist
    end

    test "includes public repos owned by the user" do
      repo = create(:repository, owner: @user, created_at: 5.years.ago)
      assert_includes @pinner.async_pinnable_items.sync, repo
    end

    test "omits public repos owned by the user when types does not include Repository" do
      repo = create(:repository, owner: @user, created_at: 5.years.ago)
      refute_includes @pinner.async_pinnable_items(types: ["Gist"]).sync, repo
    end

    test "limits the number of public repos returned" do
      other_user = create(:user)
      other_profile = create(:profile, user: other_user)
      other_pinner = ProfilePinner.new(user: other_user, viewer: other_user)
      10.times do
        repo = create(:repository, owner: other_user, created_at: 5.years.ago)
      end
      repos = other_pinner.async_pinnable_items(types: ["Repository"], repo_limit: 5).sync
      assert repos.count < 6
    end

    test "does not include inactive pinned repository" do
      inactive_repo = create(:repository)
      # Make a contribution from the user so it's pinnable by them:
      create(:issue, user: @user, repository: inactive_repo)
      create(:profile_pin, pinned_item: inactive_repo, profile: @profile)
      inactive_repo.active = nil
      inactive_repo.save!

      refute_includes @pinner.async_pinnable_items.sync, inactive_repo
    end

    test "does not include private repos owned by the user" do
      repo = create(:private_repository, owner: @user)
      refute_includes @pinner.async_pinnable_items.sync, repo
    end

    test "includes repository with recent commit by user" do
      repo = create(:repository)
      repo.add_member(@user)
      create(:commit_contribution, user: @user, repository: repo, committed_date: Time.zone.today)
      assert_includes @pinner.async_pinnable_items.sync, repo
    end

    test "does not include private repo with recent commit by user" do
      repo = create(:private_repository, owner: @user)
      create(:commit_contribution, user: @user, repository: repo, committed_date: Time.zone.today)
      refute_includes @pinner.async_pinnable_items.sync, repo
    end

    test "includes repository with recent issue by user" do
      issue = create(:issue, user: @user)
      assert_includes @pinner.async_pinnable_items.sync, issue.repository
    end

    test "does not include private repository with recent issue by user" do
      repo = create(:private_repository, owner: @user)
      create(:issue, user: @user, repository: repo)
      refute_includes @pinner.async_pinnable_items.sync, repo
    end

    test "includes repository with recent pull request by user" do
      repo = create(:repository, from_example: :pull_request_fork)
      create(:pull_request, repository: repo, issue: create(:issue, user: @user, repository: repo))
      assert_includes @pinner.async_pinnable_items.sync, repo
    end

    test "does not include private repo with recent pull request by user" do
      repo = create(:private_repository, owner: @user, from_example: :pull_request_fork)
      create(:pull_request, repository: repo, issue: create(:issue, user: @user, repository: repo))
      refute_includes @pinner.async_pinnable_items.sync, repo
    end

    test "excludes fork of a repo with user's commit when user has no other connection to it" do
      repo = create(:repository, from_example: :simple)
      only = [AddToSearchIndexJob]
      fork, _ = perform_enqueued_jobs(only: only) { repo.fork(forker: create(:user)) }
      create(:commit_contribution, repository: fork, user: @user)

      refute_includes @pinner.async_pinnable_items.sync, fork
    end

    test "includes private repo for org with viewing_as_member set to true" do
      org = create(:organization)
      viewer = create(:user)
      repo = create(:private_repository, owner: org)
      pinner = ProfilePinner.new(user: org, viewer: viewer, viewing_as_member: true)
      assert_includes pinner.async_pinnable_items.sync, repo
    end

    context "private profile" do
      test "includes collaborated repos when users is viewer" do
        @user.update_attribute(:private_profile, true)

        repo = create(:repository)
        repo.add_member(@user)
        create(:commit_contribution, user: @user, repository: repo, committed_date: Time.zone.today)
        pinner = ProfilePinner.new(user: @user, viewer: @user)
        assert_includes pinner.async_pinnable_items.sync, repo
      end
    end
  end

  context ".unpin" do
    test "unpins a pinned repository for the given user" do
      user = create(:user)
      profile = create(:profile, user: user)
      repo = create(:repository, owner: user)
      pin = create(:profile_pin, pinned_item: repo, profile: profile)

      assert_includes user.pinned_repositories, repo
      assert_difference("profile.profile_pins.count", -1) do
        ProfilePinner.unpin(repo, user: user, viewer: user)
      end

      refute ProfilePin.exists?(pin.id)
      refute_includes user.pinned_repositories, repo
    end

    test "unpins many items at once" do
      user = create(:user)
      profile = create(:profile, user: user)
      repo1 = create(:repository, owner: user)
      repo2 = create(:repository, owner: user)
      pin1 = create(:profile_pin, pinned_item: repo1, profile: profile)
      pin2 = create(:profile_pin, pinned_item: repo2, profile: profile)

      assert_includes user.pinned_repositories, repo1
      assert_difference("profile.profile_pins.count", -2) do
        ProfilePinner.unpin(repo1, repo2, user: user, viewer: user)
      end

      refute ProfilePin.exists?(pin1.id)
      refute ProfilePin.exists?(pin2.id)
      refute_includes user.pinned_repositories, repo1
      refute_includes user.pinned_repositories, repo2
    end
  end

  context ".async_pin" do
    test "allows pinning repository whose sole committer is the user" do
      user = create(:user)
      profile = create(:profile, user: user)
      org = create(:organization)
      org.add_member user
      repo = create(:repository, owner: org)
      create(:commit_contribution, user: user, repository: repo,
             committed_date: Date.new(2012, 5, 18))
      pinner = ProfilePinner.new(user: user, items: [repo], viewer: user)

      assert_difference("profile.profile_pins.count") do
        pinner.async_pin.sync
      end
    end
  end
end
