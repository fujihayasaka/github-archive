# typed: true
# frozen_string_literal: true

require "test_helper"

class UserBlockingAndUnblockTest < GitHub::TestCase
  fixtures do
    @user = create(:user, login: "free-user", email: "free-user@example.com")
    @staffer = create(:staff_admin_user, login: "staffer", plan: "medium", email: "staffer@example.com")
    @paid_user = create(:user, login: "paid-user", email: "paid-user@example.com", plan: "medium")
    @spammer = create(:user, login: "spammer", spammy: true)
    @grit    = create(:repository, name: "grit", owner: @user, from_example: :pull_request_source)

    @org = create(:organization)

    @paid_org = create(:organization, admin: @staffer, plan: GitHub::Plan.non_free_org_plans.first.name)
    @paid_org_repo = create(:repository, owner: @paid_org, from_example: :community_files)
    @paid_org_team = create(:team, organization: @paid_org)
    @paid_org_issue = create(:issue, repository: @paid_org_repo)

    oauth_app = make_oauth_app(@paid_user)
    @oauth_token = make_oauth(@user, [:repo], oauth_app).reset_token

    @staffer_grit = create(:fork_repository, forker: @staffer, fork_repo: @grit, from_example: :pull_request_fork)
  end

  context "#blocking_or_blocked_by?" do
    test "returns a hash indicating which of the given users is blocking or being blocked by the user" do
      viewer = @user
      blocked_user = @staffer
      blocking_user = @paid_user
      mutual_blocker, non_blocker = create_pair(:user)
      users = [blocked_user, blocking_user, mutual_blocker, non_blocker]

      viewer.block blocked_user
      blocking_user.block viewer
      mutual_blocker.block viewer
      viewer.block mutual_blocker

      result = assert_query_count(1) do
        viewer.blocking_or_blocked_by?(users)
      end

      assert_instance_of Hash, result
      assert result[blocked_user.id], "should be true for a blocked user"
      assert result[blocking_user.id], "should be true for a blocking user"
      assert result[mutual_blocker.id], "should be true for a blocked + blocking user"
      refute result[non_blocker.id], "should be false for a non-blocked, non-blocking user"
      refute result[viewer.id], "should be false for the user it was called on"
    end

    test "returns a hash with false for everyone when called on an unsaved user" do
      new_user = build(:user)
      users = [@staffer, @paid_user, @user]

      result = assert_query_count(0) do
        new_user.blocking_or_blocked_by?(users)
      end

      assert_instance_of Hash, result
      refute result[@staffer.id]
      refute result[@paid_user.id]
      refute result[@user.id]
    end

    test "returns a hash with false for everyone when given an empty list of users" do
      @staffer.block @user
      @user.block @paid_user

      result = assert_query_count(0) do
        @user.blocking_or_blocked_by?([])
      end

      assert_instance_of Hash, result
      refute result[@staffer.id], "should return false for blocking user who wasn't looked up"
      refute result[@paid_user.id], "should return false for blocked user who wasn't looked up"
      refute result[@user.id]
    end
  end

  context "blocking scope" do
    test "includes user who is blocking the given user" do
      freeze_time do
        viewer, blocker, non_blocker = create_list(:user, 3)
        assert blocker.block(viewer)

        result = User.blocking(viewer).where(id: [blocker, non_blocker]).pluck(:id)

        assert_includes result, blocker.id
        refute_includes result, non_blocker.id
      end
    end
  end

  context "spammy_or_blocking scope" do
    if GitHub.spamminess_check_enabled?
      test "includes spammy user for anonymous viewer" do
        assert_includes User.spammy_or_blocking(nil), @spammer
      end

      test "omits spammy user when viewed by themselves" do
        refute_includes User.spammy_or_blocking(@spammer), @spammer
      end

      test "includes spammy user for regular viewer" do
        viewer = create(:user)
        assert_includes User.spammy_or_blocking(viewer), @spammer
      end

      test "includes spammy user for staff viewer" do
        assert_includes User.spammy_or_blocking(@staffer), @spammer
      end

      test "includes spammy user who is blocking the viewer" do
        viewer = create(:user)
        assert @spammer.block(viewer)

        result = User.spammy_or_blocking(viewer).where(id: @spammer.id)

        assert_equal [@spammer], result
      end
    else
      test "does not include spammy user" do
        refute_includes User.spammy_or_blocking(nil), @spammer
      end

      test "includes spammy user who is blocking the viewer" do
        viewer = create(:user)
        assert @spammer.block(viewer)

        result = User.spammy_or_blocking(viewer).where(id: @spammer.id)

        assert_equal [@spammer], result
      end
    end

    test "includes user who is blocking the given user" do
      freeze_time do
        viewer, blocker, non_blocker = create_list(:user, 3)
        assert blocker.block(viewer)

        result = User.spammy_or_blocking(viewer).where(id: [blocker, non_blocker]).pluck(:id)

        assert_includes result, blocker.id
        refute_includes result, non_blocker.id
      end
    end
  end

  context "not_blocking scope" do
    test "includes only users who are not blocking the given user" do
      viewer, blocker, non_blocker = create_list(:user, 3)
      assert blocker.block(viewer)

      result = User.not_blocking(viewer).where(id: [blocker, non_blocker]).pluck(:id)

      assert_includes result, non_blocker.id
      refute_includes result, blocker.id
    end

    test "returns all results when no viewer is given" do
      user1, user2 = create_list(:user, 2)
      result = User.not_blocking(nil).where(id: [user1, user2])
      assert_same_elements [user1, user2], result
    end
  end

  test "user blocking" do
    refute @user.blocking?(@paid_user)
    refute @paid_user.blocked_by?(@user)

    assert @user.block(@paid_user)
    assert @user.blocking?(@paid_user)
    assert @paid_user.blocked_by?(@user)
    refute @user.block(@paid_user).valid?
    assert_equal [@user], @paid_user.ignored_by_any([@user, @paid_user])
    assert_equal [@paid_user], @user.ignoring_in([@user, @paid_user])
    @user.follow(@paid_user)
    refute @user.blocking?(@paid_user)
    refute @paid_user.blocked_by?(@user)
  end

  context "performance" do
    test "#async_blocked_by? doesn't make a query if the argument is the same user" do
      assert_queries_matching /ignored_users/, 0 do
        @user.async_blocked_by?(@user).sync
      end
    end

    test "#blocked_by? doesn't make a query if the argument is the same user" do
      assert_queries_matching /ignored_users/, 0 do
        @user.blocked_by?(@user)
      end
    end

    test "#async_blocking? doesn't make a query if the argument is the same user" do
      assert_queries_matching /ignored_users/, 0 do
        @user.async_blocking?(@user).sync
      end
    end

    test "#blocking? doesn't make a query if the argument is the same user" do
      assert_queries_matching /ignored_users/, 0 do
        @user.blocking?(@user)
      end
    end
  end

  context "user blocking with expiration" do
    test "users cannot block with expiration" do
      user = create(:user)
      refute @user.block(user, duration: 1).valid?
      refute @user.blocking?(user)
    end

    test "orgs can block with expiration" do
      user = create(:user)
      @org.block(user, duration: 1)

      assert block = IgnoredUser.where(user_id: @org.id, ignored_id: user.id).first
      assert T.must(block).expires_at
    end

    test "orgs cannot block with expiration and upgrade to permanent block" do
      user = create(:user)
      @org.block(user, duration: 1)

      assert block = IgnoredUser.where(user_id: @org.id, ignored_id: user.id).first
      assert id = T.must(block).id
      assert T.must(block).expires_at

      refute @org.block(user).valid?
      assert block = IgnoredUser.where(user_id: @org.id, ignored_id: user.id).first
      assert id, T.must(block).id
      assert T.must(block).expires_at
    end
  end

  test "unblocking a user" do
    user = create(:user)
    assert user.block(@paid_user)
    assert user.blocking?(@paid_user)
    assert user.blocking?(@paid_user, @user)
    assert user.unblock(@paid_user)
    assert user.block(@paid_user)
    assert user.unblock(@paid_user, actor: @user)
    refute user.blocking?(@paid_user)
    refute user.blocking?(@paid_user, @user)
  end

  test "an org can block a user" do
    assert @paid_org.block(@user)
    assert @user.blocked_by?(@paid_org)
  end

  test "an org cannot block one of its members" do
    refute @paid_org.block(@staffer).valid?
  end

  test "a user cannot block an org" do
    refute @user.block(@paid_org).valid?
  end

  test "a user cannot block a spammy user" do
    refute @user.block(@spammer).valid?
  end unless GitHub.enterprise?

  context "#sorted_ignored" do
    test "excludes spammy users" do
      spammy = create(:user)
      assert @org.block(spammy)
      assert_equal 1, @org.sorted_ignored.length
      spammy.update_attribute(:spammy, true)
      assert_equal 0, @org.sorted_ignored.length
    end unless GitHub.enterprise?

    test "sorts with non-expiring after expiring" do
      non_expiring = create(:user)
      expiring = create(:user)
      @org.block(non_expiring)
      @org.block(expiring, duration: 1)
      assert_equal expiring, @org.sorted_ignored.first.ignored
      assert_equal non_expiring, @org.sorted_ignored.last.ignored
    end

    test "sorts with expiring earlier first" do
      shorter = create(:user)
      longer = create(:user)
      @org.block(shorter, duration: 1)
      @org.block(longer, duration: 3)
      assert_equal shorter, @org.sorted_ignored.first.ignored
      assert_equal longer, @org.sorted_ignored.last.ignored
    end
  end

  context "forking" do
    test "forking is prevented when blocked by a user" do
      assert @paid_user.can_fork?(@grit)
      @user.block @paid_user
      refute @paid_user.can_fork?(@grit.reload)
    end

    test "forking is prevented when blocked by an org" do
      org_repo = create(:public_repository, owner: @paid_org)

      assert @paid_user.can_fork?(org_repo)
      @paid_org.block @paid_user
      refute @paid_user.can_fork?(org_repo.reload)
    end

    test "forking is prevented for private repositories with forking disabled" do
      org_repo = create(:private_repository, owner: @paid_org)
      org_repo.add_member(@paid_user, action: :read)

      assert org_repo.pullable_by?(@paid_user), "Expected user to have read access."

      refute_predicate org_repo, :allow_private_repository_forking?
      refute @paid_user.can_fork?(org_repo)

      org_repo.allow_private_repository_forking(actor: @staffer)
      assert_predicate org_repo, :allow_private_repository_forking?
      assert @paid_user.can_fork?(org_repo)
    end
  end

  context "starring" do
    test "starring is prevented and existing stars are removed when blocked by a user" do
      repo = create(:repository, owner: @user)
      @paid_user.star(repo)
      assert repo.starred_by?(@paid_user)

      perform_enqueued_jobs(only: [IgnoreUserJob]) do
        @user.block @paid_user
      end

      # permissions are now cached on the instance, so we need a new instance :)
      repo = create(:repository, owner: @user)
      refute repo.starred_by?(@paid_user)
      refute @paid_user.star(repo)
    end

    test "starring is prevented and existing stars are removed when blocked by an org" do
      org_repo = create(:public_repository, owner: @paid_org)
      @paid_user.star(org_repo)
      assert org_repo.starred_by?(@paid_user)

      perform_enqueued_jobs(only: [IgnoreUserJob]) do
        @paid_org.block @paid_user
      end

      # permissions are now cached on the instance, so we need a new instance :)
      org_repo = create(:public_repository, owner: @paid_org)
      refute org_repo.starred_by?(@paid_user)
      refute @paid_user.star(org_repo)
    end
  end

  context "creating an issue" do
    test "doesn't work if the creator is blocked by the owning user" do
      issue = @grit.issues.build(title: "irrelevant title 1", body: "irrelevant body 1")
      issue.user = @paid_user
      assert issue.save

      @user.block(@paid_user)

      issue = @grit.reload.issues.build(title: "irrelevant title 2", body: "irrelevant body 2")
      issue.user = @paid_user
      refute issue.save
    end

    test "doesn't work if the creator is blocked by the owning org" do
      org_repo = create(:public_repository, owner: @paid_org)

      issue = org_repo.issues.build(title: "irrelevant title 1", body: "irrelevant body 1")
      issue.user = @paid_user
      assert issue.save

      @paid_org.block(@paid_user)

      issue = org_repo.reload.issues.build(title: "irrelevant title 2", body: "irrelevant body 2")
      issue.user = @paid_user
      refute issue.save
    end
  end

  context "creating a pull request" do
    test "raises an error if the author is blocked by the owning user" do
      user_repo = create(:public_repository, owner: @user, from_example: :commits_controller_test)

      collaborator = create(:collaborator, repository: user_repo)
      @user.block(collaborator)

      assert_raises_with_message(ActiveRecord::RecordInvalid, /User is blocked/) do
        PullRequest.create_for!(user_repo,
          user: collaborator,
          base: "master",
          head: "topic",
          title: "Change things",
          body: "body"
        )
      end
    end

    test "raises an error if the author is blocked by the owning org" do
      org_repo = create(:public_repository, owner: @paid_org, from_example: :commits_controller_test)
      collaborator = create(:collaborator, repository: org_repo)

      @paid_org.block(collaborator)


      assert_raises_with_message(ActiveRecord::RecordInvalid, /User is blocked/) do
        PullRequest.create_for!(org_repo,
          user: collaborator,
          base: "master",
          head: "topic",
          title: "Change things",
          body: "body"
        )
      end
    end
  end

  context "creating a review comment on a pull request" do
    test "doesn't work if the creator is blocked by the owning user" do
      user_repo = create(:public_repository, owner: @user, from_example: :commits_controller_test)

      pr = PullRequest.create_for!(user_repo,
        user: @user,
        base: "master",
        head: "topic",
        title: "some changes",
      )

      comment = build(:pull_request_review_comment,
        pull_request: pr,
        user: @paid_user,
        body: "irrelevant 1",
        commit_id: pr.head_sha,
        path: "file10",
        original_position: 1,
      )
      assert_predicate comment, :valid?

      @user.block(@paid_user)
      pr.reload

      comment = build(:pull_request_review_comment,
        pull_request: pr,
        user: @paid_user,
        body: "irrelevant 2",
        commit_id: pr.head_sha,
        path: "file10",
        original_position: 1,
      )
      refute_predicate comment, :valid?
      assert_equal "is blocked", comment.errors[:user].first
    end

    test "doesn't work if the creator is blocked by the owning org" do
      org_repo = create(:public_repository, owner: @paid_org, from_example: :commits_controller_test)
      org_repo.add_member(@user)

      pr = PullRequest.create_for!(org_repo,
        user: @user,
        base: "master",
        head: "topic",
        title: "some changes",
        body: "body",
      )

      comment = build(:pull_request_review_comment,
        pull_request: pr,
        user: @paid_user,
        body: "irrelevant 1",
        commit_id: pr.head_sha,
        path: "file10",
        original_position: 1,
      )
      assert_predicate comment, :valid?

      @paid_org.block(@paid_user)
      pr.reload

      comment = build(:pull_request_review_comment,
        pull_request: pr,
        user: @paid_user,
        body: "irrelevant 2",
        commit_id: pr.head_sha,
        path: "file10",
        original_position: 1,
      )
      refute comment.valid?
      assert_equal "is blocked", comment.errors[:user].first
    end
  end

  context "commenting on an issue" do
    test "doesn't work if the commenter is blocked by the owning user" do
      issue = @grit.issues.build(title: "irrelevant title 1", body: "irrelevant body 1")
      issue.user = @user
      issue.save

      comment = issue.comments.build(body: "irrelevant body 2")
      comment.user       = @paid_user
      comment.repository = @grit
      assert comment.save

      @user.block(@paid_user)

      comment = issue.comments.build(body: "irrelevant body 3")
      comment.user       = @paid_user
      comment.repository = @grit
      refute comment.save
    end

    test "doesn't work if the commenter is blocked by the owning org" do
      org_repo = create(:public_repository, owner: @paid_org)

      issue = org_repo.issues.build(title: "irrelevant title 1", body: "irrelevant body 1")
      issue.user = @paid_org.admins.first
      issue.save

      comment = issue.comments.build(body: "irrelevant body 2")
      comment.user       = @paid_user
      comment.repository = org_repo
      assert comment.save

      @paid_org.block(@paid_user)

      comment = issue.comments.build(body: "irrelevant body 3")
      comment.user       = @paid_user
      comment.repository = org_repo
      refute comment.save
    end
  end

  context "commenting on a commit" do
    test "doesn't work if the commenter is blocked by the owning user" do
      commit    = "3572d83ba062076f6a740379463d0f3f770d7fc5"
      user_repo = create(:repository, owner: @user, from_example: :commit_comments)

      comment = CommitComment.new(
        user: @paid_user,
        repository: user_repo,
        position: 0,
        line: 0,
        path: "color.js",
        commit_id: commit,
        body: "irrelevant body 1",
      )
      assert comment.save

      @user.block(@paid_user)

      comment = CommitComment.new(
        user: @paid_user,
        repository: user_repo,
        position: 1,
        line: 1,
        path: "color.js",
        commit_id: commit,
        body: "irrelevant body 2",
      )
      refute comment.save
    end

    test "doesn't work if the commenter is blocked by the owning org" do
      commit   = "3572d83ba062076f6a740379463d0f3f770d7fc5"
      org_repo = create(:repository, owner: @paid_org, from_example: :commit_comments)

      comment = CommitComment.new(
        user: @paid_user,
        repository: org_repo,
        position: 0,
        line: 0,
        path: "color.js",
        commit_id: commit,
        body: "irrelevant body 1",
      )
      assert comment.save

      @paid_org.block(@paid_user)

      comment = CommitComment.new(
        user: @paid_user,
        repository: org_repo,
        position: 1,
        line: 1,
        path: "color.js",
        commit_id: commit,
        body: "irrelevant body 2",
      )
      refute comment.save
    end
  end

  context "creating a milestone" do
    test "doesn't work if the creator is blocked by the owning user" do
      milestone = build(:milestone, repository: @grit, created_by: @paid_user)
      assert milestone.save

      @user.block(@paid_user)

      milestone = build(:milestone, repository: @grit.reload, created_by: @paid_user)
      refute milestone.save
    end

    test "doesn't work if the creator is blocked by the owning org" do
      org_repo  = create(:repository, owner: @paid_org)
      milestone = build(:milestone, repository: org_repo, created_by: @paid_user)
      assert milestone.save

      @paid_org.block(@paid_user)

      milestone = build(:milestone, repository: org_repo.reload, created_by: @paid_user)
      refute milestone.save
    end
  end

  context "creating a wiki page" do
    test "doesn't work if the creator is blocked by the owning user" do
      user_wiki_repo = create(:repository, owner: @user, has_wiki: true)
      wiki           = user_wiki_repo.unsullied_wiki
      example_repo :wiki_controller_public, wiki

      refute_nil wiki.pages.create("irrelevantname1", "markdown", "irrelevant data 1", "irrelevant message 1", @paid_user)

      @user.block(@paid_user)

      assert_raises GitHub::Unsullied::Wiki::UnwantedEditError do
        wiki.pages.create("irrelevantname2", "markdown", "irrelevant data 2", "irrelevant message 2", @paid_user)
      end
    end

    test "doesn't work if the creator is blocked by the owning org" do
      org_wiki_repo = create(:repository, owner: @paid_org, has_wiki: true)
      wiki          = org_wiki_repo.unsullied_wiki
      example_repo :wiki_controller_public, wiki

      refute_nil wiki.pages.create("irrelevantname1", "markdown", "irrelevant data 1", "irrelevant message 1", @paid_user)

      @paid_org.block(@paid_user)

      assert_raises GitHub::Unsullied::Wiki::UnwantedEditError do
        wiki.pages.create("irrelevantname2", "markdown", "irrelevant data 2", "irrelevant message 2", @paid_user)
      end
    end
  end

  context "editing a wiki page" do
    test "doesn't work if the editor is blocked by the owning user" do
      user_wiki_repo = create(:repository, owner: @user, has_wiki: true)
      wiki           = user_wiki_repo.unsullied_wiki
      example_repo :wiki_controller_public, wiki

      page = wiki.pages.create("irrelevantname", "markdown", "irrelevant data", "irrelevant message", @user)

      updated_page = page.update("newname1", page.data, page.format, "irrelevant message", @paid_user)
      assert_equal "newname1", updated_page.name

      @user.block(@paid_user)

      assert_raises GitHub::Unsullied::Wiki::UnwantedEditError do
        updated_page.update("newname2", page.data, page.format, "irrelevant message", @paid_user)
      end
    end

    test "doesn't work if the editor is blocked by the owning org" do
      org_wiki_repo = create(:repository, owner: @paid_org, has_wiki: true)
      wiki          = org_wiki_repo.unsullied_wiki
      example_repo :wiki_controller_public, wiki

      page = wiki.pages.create("irrelevantname", "markdown", "irrelevant data", "irrelevant message", @paid_org.admins.first)

      updated_page = page.update("newname1", page.data, page.format, "irrelevant message", @paid_user)
      assert_equal "newname1", updated_page.name

      @paid_org.block(@paid_user)

      assert_raises GitHub::Unsullied::Wiki::UnwantedEditError do
        updated_page.update("newname2", page.data, page.format, "irrelevant message", @paid_user)
      end
    end
  end

  context "avoiding" do
    test "user avoids blocked user" do
      refute @user.avoid?(@paid_user)
      @user.block @paid_user
      assert @user.avoid?(@paid_user)
      assert_equal :ignore, @user.avoidable_reason_for(@paid_user)
    end

    test "user avoids user blocking them" do
      refute @user.avoid?(@paid_user)
      @paid_user.block @user
      assert @user.avoid?(@paid_user)
      assert_equal :ignored_by, @user.avoidable_reason_for(@paid_user)
    end

    test "user avoids spammy user" do
      skip "spamminess checks are not enabled on Enterprise" unless GitHub.spamminess_check_enabled?
      spammer = create(:user)
      refute @paid_user.avoid?(spammer)
      spammer.mark_as_spammy
      assert spammer.spammy?
      assert @paid_user.avoid?(spammer)
      assert_equal :bad_actor, @paid_user.avoidable_reason_for(spammer)
    end

    test "user avoids suspended user" do
      GitHub.override(:suspended_users_visible, false) do
        bad_actor = create(:user)
        refute @paid_user.avoid?(bad_actor)
        bad_actor.suspend("test")
        assert bad_actor.suspended?
        assert @paid_user.avoid?(bad_actor)
        assert_equal :bad_actor, @paid_user.avoidable_reason_for(bad_actor)
      end
    end
  end

  context "bad actor" do
    test "user is not a bad actor" do
      refute @user.bad_actor?
    end

    test "suspended user is a bad actor" do
      GitHub.override(:suspended_users_visible, false) do
        user = create(:user)
        user.suspend("test")
        assert user.bad_actor?
      end
    end

    test "spammy user is a bad actor" do
      skip "spamminess checks are not enabled on Enterprise" unless GitHub.spamminess_check_enabled?
      user = create(:user)
      user.mark_as_spammy
      assert user.bad_actor?
    end
  end

  context "ignoring_in" do
    test "gets the set of users a user has blocked from an array of users" do
      user = create(:user)
      user.block(@paid_user)
      # works with users
      assert_equal [@paid_user], user.ignoring_in([@user, @paid_user])
      # works with IDs
      assert_equal [@paid_user], user.ignoring_in([@user.id, @paid_user.id])
    end

    test "gets the set of users an org has blocked from an array of users" do
      @paid_org.block(@paid_user)

      # works with users
      assert_equal [@paid_user], @paid_org.ignoring_in([@user, @paid_user])

      # works with IDs
      assert_equal [@paid_user], @paid_org.ignoring_in([@user.id, @paid_user.id])
    end
  end

  context "can_block?" do
    test "a user can block any other user" do
      assert @paid_user.can_block(@user).blockable?
      assert @user.can_block(@paid_user).blockable?
    end

    test "an org can block a non-member" do
      assert @paid_org.can_block(@user).blockable?
    end

    test "an org cannot block one of its own members" do
      can_block = @paid_org.can_block(@staffer)
      refute can_block.blockable?
      assert_equal "Blocked user is an organization member", can_block.reason
    end

    test "a user cannot block a spammy user" do
      can_block = @user.can_block(@spammer)
      refute can_block.blockable?
      assert_equal "Blocked user has been flagged as spam", can_block.reason
    end unless GitHub.enterprise?

    if GitHub.email_verification_enabled?
      test "a user without any verified emails cannot block" do
        GitHub.stubs(:mandatory_email_verification_enabled?).returns(true)
        @user.require_email_verification!
        @user.emails.each(&:unverify!)
        can_block = @user.can_block(@paid_user)
        refute can_block.blockable?
        assert_equal "Blocking user cannot block without a verified email", can_block.reason
      end
    end
  end

  context "stats" do
    test "user blocking is tracked" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      @user.block(@paid_user)

      stat = GitHub.dogstats.increments("user.blocked")[0]
      assert stat, "Expected a user.blocked stat to have been set"
      assert_equal ["blocked_by:user", "duration:indefinite"].to_set, stat.tags
    end

    test "user unblocking is tracked" do
      @user.block(@paid_user)
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      @user.unblock(@paid_user)

      stat = GitHub.dogstats.operations.find { |operation| operation.stat == "user.unblocked" }
      assert stat, "Expected a user.unblocked stat to have been set"
      assert_equal ["blocked_by:user"].to_set, stat.tags
    end

    test "org blocking a user is tracking via separate stat metric" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      @paid_org.block(@user)

      stat = GitHub.dogstats.operations.find { |operation| operation.stat == "user.blocked" }
      assert stat, "Expected a user.blocked stat to have been set"
      assert_equal ["blocked_by:org", "duration:indefinite", "content_type:unknown", "minimize_reason:none", "code_of_conduct_status:unknown", "send_notification:false"].to_set, stat.tags
    end

    test "org blocking a user with all fields correctly records all fields" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      issue_comment = create(:issue_comment, user: @user, issue: @paid_org_issue)
      @paid_org.block(@user, duration: 3, blocked_from_content: issue_comment, send_notification: true, minimize_reason: "spam")

      stat = GitHub.dogstats.operations.find { |operation| operation.stat == "user.blocked" }
      assert stat, "Expected a user.blocked stat to have been set"
      assert_equal ["blocked_by:org", "duration:3-days", "content_type:IssueComment", "minimize_reason:spam", "code_of_conduct_status:true", "send_notification:true"].to_set, stat.tags
    end

    if GitHub.email_verification_enabled?
      test "spammy user blocking does not generate stats" do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
        @user.update_attribute(:spammy, true)
        @user.block(@paid_user)

        stat = GitHub.dogstats.increments("user.blocked")[0]
        refute stat
      end
    end
  end

  context "instrumentation" do
    test "blocking a user is instrumented" do
      events = subscribe "user.block_user"
      assert @user.block(@paid_user)

      expected_payload = {
        actor: @user.login,
        actor_id: @user.id,
        blocked_user: @paid_user.login,
        blocked_user_id: @paid_user.id,
        user: @user.login,
        user_id: @user.id,
        expires_at: nil,
        duration: nil,
        spammy: false,
        blocked_from_content_id: nil,
        blocked_from_content_type: nil,
        send_notification: false,
        minimize_reason: nil,
        code_of_conduct_status: "unknown",
      }
      assert event = events.pop, "an event should've been created"
      assert_equal "user.block_user", event.name
      assert_equal expected_payload, event.payload
    end

    test "an org blocking a user is instrumented" do
      events = subscribe "org.block_user"
      issue_comment = create(:issue_comment, user: @user, issue: @paid_org_issue)
      @paid_org.block(@user, actor: @staffer, blocked_from_content: issue_comment, send_notification: true, minimize_reason: "spam")

      expected_payload = {
        actor: @staffer.login,
        actor_id: @staffer.id,
        org: @paid_org.login,
        org_id: @paid_org.id,
        blocked_user: @user.login,
        blocked_user_id: @user.id,
        expires_at: nil,
        duration: nil,
        spammy: false,
        blocked_from_content_id: issue_comment.id,
        blocked_from_content_type: "IssueComment",
        send_notification: true,
        minimize_reason: "spam",
        code_of_conduct_status: true,
      }
      assert event = events.pop, "an event should've been created"
      assert_equal "org.block_user", event.name
      assert_equal expected_payload, event.payload
    end

    test "unblocking a user is instrumented" do
      events = subscribe "user.unblock_user"
      assert @user.block(@paid_user)
      assert @user.unblock(@paid_user)

      expected_payload = {
        actor: @user.login,
        actor_id: @user.id,
        blocked_user: @paid_user.login,
        blocked_user_id: @paid_user.id,
        user: @user.login,
        user_id: @user.id,
        spammy: false,
      }
      assert event = events.pop, "an event should've been created"
      assert_equal "user.unblock_user", event.name
      assert_equal expected_payload, event.payload
    end

    test "unblocking a non-blocked user isn't instrumented" do
      @user.unblock(@paid_user)
      events = subscribe "user.unblock_user"

      @user.unblock(@paid_user)
      refute events.pop, "an event shouldn't have been created"
    end
  end

  context "#blocked_users_manageable_by?" do
    test "returns true for user managing self" do
      assert @user.blocked_users_manageable_by?(@user)
      assert @user.async_blocked_users_manageable_by?(@user).sync
    end

    test "returns true for org owner managing org" do
      assert @org.blocked_users_manageable_by?(@org.admin)
      assert @org.async_blocked_users_manageable_by?(@org.admin).sync
    end

    if GitHub.user_abuse_mitigation_enabled?
      test "returns true for org moderator" do
        @org.add_member(@user)
        @org.moderation.add_moderator(@user, actor: @org.admin)
        refute @org.adminable_by?(@user)
        assert @org.moderator?(@user)

        assert @org.blocked_users_manageable_by?(@user)
        assert @org.async_blocked_users_manageable_by?(@user).sync
      end
    end

    test "returns false for user managing other user" do
      refute @staffer.blocked_users_manageable_by?(@user)
      refute @staffer.async_blocked_users_manageable_by?(@user).sync
    end

    test "returns false for org member" do
      @org.add_member(@user)
      refute @org.blocked_users_manageable_by?(@user)
      refute @org.async_blocked_users_manageable_by?(@user).sync
    end

    test "returns false for nil user" do
      refute @org.blocked_users_manageable_by?(nil)
      refute @org.async_blocked_users_manageable_by?(nil).sync
    end
  end
end
