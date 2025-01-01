# typed: true
# frozen_string_literal: true

require "test_helper"

class UserContributionsTest < GitHub::TestCase
  fixtures do
    @owner = create(:user, plan: "gold", login: "owner")
    @johndoe = create(:user, login: "johndoe", created_at: 1.month.ago)
    @janedoe = create(:user, login: "janedoe", created_at: 1.month.ago)

    @public_repo = create :repository, name: "some-repo", owner: @owner, from_example: :review_comment_source
    @private_repo = create :private_repository, owner: @owner, name: "private-repo"

    @private_repo.add_member @johndoe
    @private_repo.add_member @janedoe

    @private_issue = create :issue, repository: @private_repo,
      user: @johndoe,
      created_at: (Time.zone.now - 1.day),
      contributed_at: (Time.zone.now - 1.day)

    @public_issue = create :issue, repository: @public_repo,
      user: @johndoe,
      created_at: (Time.zone.now - 1.day),
      contributed_at: (Time.zone.now - 1.day)

    @contributor = create(:user)
    @rando = create(:user)
    @user_repo = create(:repository, owner: @contributor)
    @private_user_repo = create(:private_repository, owner: @contributor)
    @private_rando_repo = create(:private_repository, owner: @rando)
  end

  setup do
    reset_cache
  end

  test "includes public repos user has contributed to" do
    assert_includes @johndoe.repositories_contributed_to, @public_repo
  end

  test "does not include private repo for anon users" do
    refute_includes @johndoe.repositories_contributed_to, @private_repo
  end

  test "does not include private repos for users without access" do
    random_user = create(:user)
    refute_includes @johndoe.repositories_contributed_to(viewer: random_user), @private_repo
  end

  test "includes private repos for users with access" do
    assert_includes @johndoe.repositories_contributed_to(viewer: @janedoe), @private_repo
  end

  test "excludes this users owned repos by default" do
    other_repo = create(:repository, name: "my_repo", owner: @johndoe)

    create(:issue, user: @owner, repository: other_repo)
    create(:issue, user: @owner, repository: @public_repo)

    contributed_repos = @owner.repositories_contributed_to

    refute_includes contributed_repos, @public_repo
    assert_includes contributed_repos, other_repo
  end

  unless GitHub.enterprise?
    test "excludes repos that have been disabled" do
      staff = create(:staff_admin_user)
      @johndoe = User.find(@johndoe.id) # reset any instance memoization
      dmca_url = "https://github.com/github/dmca/blob/master/2011/2011-01-27-sony.markdown"

      @public_repo.access.disable("dmca", staff, dmca_takedown: dmca_url)

      refute_includes @johndoe.repositories_contributed_to, @public_repo
    end
  end

  test "optionally includes this users owned repos" do
    other_repo = create(:repository, name: "repo", owner: @johndoe)

    create(:issue, user: @owner, repository: @public_repo)
    create(:issue, user: @owner, repository: other_repo)

    contributed_repos = @owner.repositories_contributed_to(exclude_owned: false)

    assert_includes contributed_repos, @public_repo
    assert_includes contributed_repos, other_repo
  end

  test "returns higher ranking repositories first" do
    repo_rank_1 = create :repository, name: "repo-rank-1"
    create :issue, user: @johndoe, repository: repo_rank_1
    create :issue, user: @johndoe, repository: repo_rank_1
    create :issue, user: @johndoe, repository: repo_rank_1

    repo_rank_2 = create :repository, name: "repo-rank-2"
    create :issue, user: @johndoe, repository: repo_rank_2
    create :issue, user: @johndoe, repository: repo_rank_2

    repo_rank_3 = create :repository, name: "repo-rank-3"
    create :issue, user: @johndoe, repository: repo_rank_3

    assert_equal [repo_rank_1, repo_rank_2, repo_rank_3, @public_repo], @johndoe.reload.repositories_contributed_to
  end

  context "#contribution_classes" do
    test "defaults to Contribution::Collector::CONTRIBUTION_CLASSES_ASSOCIATED_WITH_REPOS" do
      user = create(:user)
      default_classes = Contribution::Collector::CONTRIBUTION_CLASSES_ASSOCIATED_WITH_REPOS
      default_classes.each do |klass|
        assert_includes user.contribution_classes, klass
      end
    end

    test "includes Contribution::CreatedIssueComment when include_issue_comments is true" do
      user = create(:user)

      expected_classes = Contribution::Collector::CONTRIBUTION_CLASSES_ASSOCIATED_WITH_REPOS +
        [Contribution::CreatedIssueComment]
      actual_classes = user.contribution_classes(include_issue_comments: true)

      assert_equal actual_classes.count, expected_classes.count
      expected_classes.each do |klass|
        assert_includes actual_classes, klass
      end
    end
  end

  context "with caching turned on" do
    test "for anonymous viewers, excludes repos that got cached when they were public but are now private" do
      enable_cache_storage
      repo = @public_repo

      begin
        assert_includes @johndoe.repositories_contributed_to, repo

        repo.toggle_visibility(actor: repo.owner)
        assert repo.reload.private?, "repo should be private now"

        @johndoe = User.find(@johndoe.id) # reset any instance memoization

        refute_includes @johndoe.repositories_contributed_to, repo
      ensure
        disable_cache_storage
      end
    end

    test "for authed viewers, excludes repos that got cached when they were accessible but are now inaccessible" do
      enable_cache_storage
      random_user = create :user, plan: "gold"

      begin
        @private_repo.add_member random_user
        assert_includes random_user.associated_repository_ids, @private_repo.id

        assert_includes @johndoe.repositories_contributed_to(viewer: random_user), @private_repo

        @private_repo.remove_member random_user
        refute_includes random_user.associated_repository_ids, @private_repo.id
        refute_includes @johndoe.repositories_contributed_to(viewer: random_user), @private_repo
      ensure
        disable_cache_storage
      end
    end

  end

  context "User#add_email" do
    test "rebuilds contributions by default" do
      @janedoe.expects(:rebuild_contributions).once
      @janedoe.add_email "foo@bar.com"
    end

    test "can disable rebuilding contributions" do
      @janedoe.expects(:rebuild_contributions).never
      @janedoe.add_email "foo@bar.com", rebuild_contributions: false
    end
  end

  context "#repositories_contributed_to" do
    test "filters private repos" do
      create_contribution(@private_user_repo, @contributor)
      create_contribution(@user_repo, @contributor)
      create_contribution(@private_rando_repo, @contributor)

      result = @contributor.repositories_contributed_to(viewer: @contributor, exclude_owned: false, repo_type: "private", since: 1.year.ago)

      assert result.all?(&:private?)
      assert_includes result, @private_user_repo

      refute result.any?(&:archived?)
      refute_includes result, @private_rando_repo
      refute_includes result, @user_repo
    end

    test "filters public repos" do
      create_contribution(@private_user_repo, @contributor)
      create_contribution(@user_repo, @contributor)

      result = @contributor.repositories_contributed_to(viewer: @contributor, exclude_owned: false, repo_type: "public", since: 1.year.ago)

      assert result.all?(&:public?)
      assert_includes result, @user_repo

      refute result.any?(&:archived?)
      refute_includes result, @private_user_repo
    end

    test "filters template repos" do
      template_repo = create(:repository, :template, owner: @rando)
      create_contribution(template_repo, @contributor)
      create_contribution(@user_repo, @contributor)

      result = @contributor.repositories_contributed_to(viewer: @contributor, exclude_owned: false, repo_type: "template", since: 1.year.ago)

      assert result.all?(&:template?)
      assert_includes result, template_repo

      refute result.any?(&:archived?)
      refute_includes result, @user_repo
    end

    test "filters mirror repos" do
      mirrored_repo = create(:mirror_repository, owner: @rando)
      create_contribution(mirrored_repo, @contributor)
      create_contribution(@user_repo, @contributor)

      result = @contributor.repositories_contributed_to(viewer: @contributor, exclude_owned: false, repo_type: "mirror", since: 1.year.ago)

      assert result.all?(&:mirror?)
      assert_includes result, mirrored_repo

      refute result.any?(&:archived?)
      refute_includes result, @user_repo
    end

    test "filters forked repos" do
      forked_repo = create(:fork_repository, forker: @rando, fork_repo: @user_repo)
      create_contribution(forked_repo, @contributor)
      create_contribution(@user_repo, @contributor)

      result = @contributor.repositories_contributed_to(viewer: @contributor, exclude_owned: false, repo_type: "fork", since: 1.year.ago)

      assert result.all?(&:fork?)
      assert_includes result, forked_repo

      refute result.any?(&:archived?)
      refute_includes result, @user_repo
    end

    test "filters source repos" do
      forked_repo = create(:fork_repository, forker: @rando, fork_repo: @user_repo)
      mirrored_repo = create(:mirror_repository, owner: @rando)
      create_contribution(forked_repo, @contributor)
      create_contribution(mirrored_repo, @contributor)
      create_contribution(@user_repo, @contributor)

      result = @contributor.repositories_contributed_to(viewer: @contributor, exclude_owned: false, repo_type: "source", since: 1.year.ago)

      assert_includes result, @user_repo

      refute result.any?(&:fork?)
      refute result.any?(&:mirror?)
      refute result.any?(&:archived?)
      refute_includes result, forked_repo
      refute_includes result, mirrored_repo
    end

    test "filters archived repos" do
      create_contribution(@user_repo, @contributor)

      archived_repo = create(:repository, owner: @rando).tap do |repo|
        create_contribution(repo, @contributor)
        repo.set_archived
      end

      result = @contributor.repositories_contributed_to(viewer: @contributor, exclude_owned: false, repo_type: "archived", since: 1.year.ago)

      assert result.all?(&:archived?)
      assert_includes result, archived_repo

      refute_includes result, @user_repo
    end
  end

  context "#ranked_contributed_repositories" do
    test "ranks contributed repositories by commits, issues, and PRs" do
      user  = create :user, login: "contributor"
      repo1 = create :repository, name: "one"
      repo2 = create :repository, name: "two"
      repo3 = create :repository, name: "three"
      repo4 = create :repository, name: "four"

      repo1.add_member user
      repo2.add_member user
      repo3.add_member user
      repo4.add_member user

      # Repo 1 - 1 Commit contribution with 2 commits happening today
      create(:commit_contribution,
        repository: repo1,
        user: user,
        commit_count: 2,
        committed_date: Time.zone.today)

      # Repo 2: Two commit contributions, one today, one yesterday
      create(:commit_contribution,
        repository: repo2,
        user: user,
        commit_count: 1,
        committed_date: Time.zone.today)

      create(:commit_contribution,
        repository: repo2,
        user: user,
        commit_count: 1,
        committed_date: 1.day.ago.to_date)

      # Repo 3: An issue and commit contribution
      create(:commit_contribution,
        repository: repo3,
        user: user,
        commit_count: 1,
        committed_date: Time.zone.today)

      user.issues.create! \
        repository: repo3,
        title: "Mo Money, Mo Problems"

      3.times do
        user.issues.create! repository: repo4, title: "Yup"
      end

      contributions = user.ranked_contributed_repositories
      repos = contributions.keys

      assert_equal 4.0, contributions[repo1][:score]
      assert_equal 3.0, contributions[repo2][:score]
      assert_equal 2.5, contributions[repo3][:score]

      assert_equal 4, repos.size
      assert_equal repo1, repos[0]
      assert_equal repo2, repos[1]
      assert_equal repo3, repos[2]
      assert_equal repo4, repos[3]
    end

    test "counts commits in source when user has a fork" do
      GitHub.flipper[:commit_contribution_summaries].disable
      GitHub.flipper[:update_existing_commit_contribution_summaries].disable

      forker = create(:user, login: "bwalsh")
      create(:fork_repository, forker: forker, fork_repo: @public_repo)
      forker.update email: "rtomayko@gmail.com"
      CommitContribution.backfill!(@public_repo)
      Timecop.freeze do
        @public_repo.commit_contributions.each_with_index do |commit, index|
          commit.update_column :committed_date, index.days.ago
        end
      end

      repos = forker.ranked_contributed_repositories
      assert_equal @public_repo, repos.keys[0]
    end

    test "counts commits when the user is a collaborator" do
      GitHub.flipper[:commit_contribution_summaries].disable
      GitHub.flipper[:update_existing_commit_contribution_summaries].disable

      user = create :user, email: "rtomayko@gmail.com"
      CommitContribution.backfill!(@public_repo)

      Timecop.freeze do
        @public_repo.commit_contributions.each_with_index do |commit, index|
          commit.update_column :committed_date, index.days.ago
        end
      end

      @public_repo.add_member user
      repos = user.ranked_contributed_repositories
      assert_equal @public_repo, repos.keys[0]
    end

    test "counts commits when the user has opened an issue" do
      GitHub.flipper[:commit_contribution_summaries].disable
      GitHub.flipper[:update_existing_commit_contribution_summaries].disable

      user = create :user, email: "rtomayko@gmail.com"
      CommitContribution.backfill!(@public_repo)
      Timecop.freeze do
        @public_repo.commit_contributions.each_with_index do |commit, index|
          commit.update_column :committed_date, index.days.ago
        end
      end

      create :issue, repository: @public_repo, user: user
      repos = user.ranked_contributed_repositories
      assert_equal @public_repo, repos.keys[0]
    end

    test "counts commits when the user has starred the repository and feature flag is disabled" do
      GitHub.flipper[:commit_contribution_summaries].disable
      GitHub.flipper[:update_existing_commit_contribution_summaries].disable
      GitHub.flipper[:disable_starred_repo_validation].disable
      user = create :user, email: "rtomayko@gmail.com"
      CommitContribution.backfill!(@public_repo)
      Timecop.freeze do
        @public_repo.commit_contributions.each_with_index do |commit, index|
          commit.update_column :committed_date, index.days.ago
        end
      end

      user.star @public_repo
      repos = user.ranked_contributed_repositories
      assert_equal @public_repo, repos.keys[0]
    end

    test "does not count commits when the user has starred the repository and feature flag is enable" do
      GitHub.flipper[:disable_starred_repo_validation].enable
      user = create :user, email: "rtomayko@gmail.com"
      CommitContribution.backfill!(@public_repo)
      Timecop.freeze do
        @public_repo.commit_contributions.each_with_index do |commit, index|
          commit.update_column :committed_date, index.days.ago
        end
      end

      user.star @public_repo
      repos = user.ranked_contributed_repositories
      assert_empty repos.keys
    end

    test "counts commits when the user is in the repo's org" do
      GitHub.flipper[:commit_contribution_summaries].disable
      GitHub.flipper[:update_existing_commit_contribution_summaries].disable

      user = create :user, email: "rtomayko@gmail.com"
      org = create(:organization)
      public_repo = create :repository, owner: org, from_example: :review_comment_source
      team = create(:team, organization: org)
      team.add_member user

      CommitContribution.backfill!(public_repo)
      Timecop.freeze do
        public_repo.commit_contributions.each_with_index do |commit, index|
          commit.update_column :committed_date, index.days.ago
        end
      end

      repos = user.ranked_contributed_repositories
      assert_equal public_repo, repos.keys[0]
    end

    test "counts commits within a custom timeframe" do
      GitHub.flipper[:commit_contribution_summaries].disable
      GitHub.flipper[:update_existing_commit_contribution_summaries].disable

      user = create :user, email: "rtomayko@gmail.com"
      org = create(:organization)
      team = create(:team, organization: org)
      team.add_member user
      other_public_repo = create :repository, name: "other-repo", owner: org, from_example: :review_comment_source

      CommitContribution.backfill!(@public_repo)
      CommitContribution.backfill!(other_public_repo)

      Timecop.freeze(4.months.ago) do
        @public_repo.commit_contributions.each_with_index do |commit, index|
          commit.update_column :committed_date, index.days.ago
        end
      end
      Timecop.freeze(2.months.ago) do
        other_public_repo.commit_contributions.each_with_index do |commit, index|
          commit.update_column :committed_date, index.days.ago
        end
      end

      user.star @public_repo
      user.star other_public_repo
      repos = user.ranked_contributed_repositories(since: 3.months.ago)
      keys = repos.keys

      refute_includes keys, @public_repo
      assert_includes keys, other_public_repo
    end

    test "doesn't counts commits if the user hasn't interacted with the repo" do
      user = create :user, email: "rtomayko@gmail.com"
      CommitContribution.backfill!(@public_repo)
      Timecop.freeze do
        @public_repo.commit_contributions.each_with_index do |commit, index|
          commit.update_column :committed_date, index.days.ago
        end
      end

      assert_equal Hash.new, user.ranked_contributed_repositories
    end
  end

  context "#flag_as_large_scale_contributor!" do
    test "sets the large-scale contributor flag on the user" do
      refute @johndoe.large_scale_contributor?
      @johndoe.flag_as_large_scale_contributor!
      assert @johndoe.large_scale_contributor?
    end

    test "works fine if called multiple times" do
      @johndoe.flag_as_large_scale_contributor!
      assert @johndoe.large_scale_contributor?

      @johndoe.flag_as_large_scale_contributor!
      assert @johndoe.large_scale_contributor?
    end

    test "creates an audit log event" do
      events = subscribe "user.flag_as_large_scale_contributor"

      expected_payload = {
        user: @johndoe.login,
        user_id: @johndoe.id,
        actor: @johndoe.login,
        actor_id: @johndoe.id,
      }

      @johndoe.flag_as_large_scale_contributor!

      assert event = events.pop, "an event was expected"
      assert_equal "user.flag_as_large_scale_contributor", event.name
      assert_equal expected_payload, event.payload
    end
  end

  context "#remove_large_scale_contributor_flag" do
    test "removes the large-scale contributor flag on the user" do
      @johndoe.flag_as_large_scale_contributor!
      assert @johndoe.large_scale_contributor?

      @johndoe.remove_large_scale_contributor_flag!
      refute @johndoe.large_scale_contributor?
    end

    test "creates an audit log event" do
      events = subscribe "user.remove_large_scale_contributor_flag"

      expected_payload = {
        user: @johndoe.login,
        user_id: @johndoe.id,
        actor: @johndoe.login,
        actor_id: @johndoe.id,
      }

      @johndoe.remove_large_scale_contributor_flag!

      assert event = events.pop, "an event was expected"
      assert_equal "user.remove_large_scale_contributor_flag", event.name
      assert_equal expected_payload, event.payload
    end
  end

  context "#large_scale_contributor?" do
    test "true if the user has the large-scale contributor flag set" do
      @johndoe.flag_as_large_scale_contributor!
      assert @johndoe.large_scale_contributor?
    end

    test "false if the user does not have the large-scale contributor flag set" do
      refute @johndoe.large_scale_contributor?
    end
  end

  context "#flag_contribution_classes!" do
    test "sets the flagged contribution classes on the user" do
      actor = create(:user)

      assert_empty @johndoe.flagged_contribution_classes

      @johndoe.flag_contribution_classes!([Contribution::CreatedCommit], actor: actor)

      assert_equal [Contribution::CreatedCommit], @johndoe.flagged_contribution_classes
    end

    test "creates an audit log event" do
      actor = create(:user)
      events = subscribe "user.flag_contribution_classes"

      expected_payload = {
        user: @johndoe.login,
        user_id: @johndoe.id,
        actor: actor.login,
        actor_id: actor.id,
        contribution_classes: "Contribution::CreatedCommit",
      }

      @johndoe.flag_contribution_classes!([Contribution::CreatedCommit], actor: actor)

      assert event = events.pop, "an event was expected"
      assert_equal "user.flag_contribution_classes", event.name
      assert_equal expected_payload, event.payload
    end
  end

  context "#flagged_contribution_classes" do
    test "returns the flagged contribution classes" do
      actor = create(:user)
      flagged_contribution_classes = [Contribution::CreatedCommit, Contribution::CreatedIssue]
      @johndoe.flag_contribution_classes!(flagged_contribution_classes, actor: actor)

      assert_equal flagged_contribution_classes, @johndoe.flagged_contribution_classes
    end

    test "returns empty array if the user does not have any flagged contribution classes" do
      assert_equal [], @johndoe.flagged_contribution_classes
    end

    test "automatically removes invalid class names from the list" do
      actor = create(:user)
      @johndoe.flag_contribution_classes!([Contribution::CreatedCommit, "Does::NotExist"], actor: actor)

      assert_equal [Contribution::CreatedCommit], @johndoe.flagged_contribution_classes
    end
  end

  def create_contribution(repo, user)
    create(:issue, user: user, repository: repo).tap do |_|
      repo.reload
    end
  end
end
