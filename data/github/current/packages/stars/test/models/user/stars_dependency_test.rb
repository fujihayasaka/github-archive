# typed: false
# frozen_string_literal: true

require "test_helper"

class UserStarsDependencyTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @defunkt = create(:staff_admin_user, login: "defunkt", plan: "medium", email: "chris@ozmm.org")
    @mojombo = create(:user, login: "mojombo", email: "tom@mojombo.com")
    @pj      = create(:user, login: "pj", email: "pjhyett@gmail.com", plan: "medium")
    @maddox  = create(:user, login: "maddox")
    @spammer = create(:user, login: "dr-evil", spammy: true)
    @grit    = create(:repository, name: "grit", owner: @mojombo, from_example: :pull_request_source)
    @ambition = create(:private_repository, name: "ambition", owner: @defunkt)
    @facebox  = create(:repository, name: "facebox", owner: @defunkt)
    @github   = create(:repository, name: "github", owner: @defunkt)

    @js = create(:language_name, name: "JavaScript", linguist_id: 183)
    @ruby = create(:language_name, name: "Ruby", linguist_id: 326)

    @paid_org = create(:organization, admin: @defunkt, plan: GitHub::Plan.non_free_org_plans.first.name)
    @paid_org_team = create(:team, organization: @paid_org)

    oauth_app = make_oauth_app(@pj)
    @oauth_token = make_oauth(@mojombo, [:repo], oauth_app).reset_token

    @defunkt_grit = create(:fork_repository, forker: @defunkt, fork_repo: @grit, from_example: :pull_request_fork)
  end

  setup do
    GitHub.preview_features_enabled = true
  end

  test "can retrieve the count of starred topics" do
    topic = create(:topic)
    create(:star, user: @user, starrable: topic)

    assert_equal 1, @user.starred_topics_count
  end

  test "can star a repo" do
    refute_includes @pj.starred_repositories, @grit
    @pj.star @grit
    assert_includes @pj.reload.starred_repositories, @grit
    refute_empty Stars.domain.user_starred_repository_ids(@pj.id, repo_ids: [@grit.id])
  end

  test "doesn't star a newly created repo by default" do
    repo = create(:repository, name: "auto_migrations", owner: @pj)
    refute_includes @pj.reload.starred_repositories, repo
  end

  test "can unstar a repo she has starred" do
    @defunkt.star(@grit)
    assert_includes @defunkt.starred_repositories, @grit
    success = @defunkt.unstar @grit
    assert success
    refute_includes @defunkt.reload.starred_repositories, @grit
  end

  test "unstars repo when un-collab'd" do
    @ambition.add_member @mojombo
    @mojombo.star(@ambition)
    assert_includes @mojombo.starred_repositories, @ambition
    only = [RemoveUserFromRepoCleanupJob]
    perform_enqueued_jobs(only: only) do
      @ambition.remove_member(@mojombo)
    end
    assert !@ambition.pullable_by?(@mojombo)
    refute_includes @mojombo.reload.starred_repositories, @ambition
  end

  test "unstars repo when de-team'd" do
    user = create(:user)
    org = create :organization, admin: @defunkt, plan: "bronze"
    org.update_default_repository_permission(:none, actor: org.admins.first)

    repo = create(:private_repository, owner: org)
    team = create :team, organization: org
    team.add_repository repo, :pull
    team.add_member user

    assert repo.pullable_by?(user)
    user.star(repo)
    assert_includes user.starred_repositories, repo

    perform_enqueued_jobs(only: [ClearTeamMembershipsJob]) { team.remove_member(user) }
    repo.reload

    assert !repo.pullable_by?(user.reload)
    refute_includes user.reload.starred_repositories, repo
  end

  test "can unstar a repo she hasn't starred just fine" do
    refute_includes @pj.starred_repositories, @github
    success = @pj.unstar @github
    refute success
    refute_includes @pj.reload.starred_repositories, @github
  end

  test "knows if he has starred a repo" do
    Stars.domain.star_repository(repository: @grit, user: @defunkt)

    assert Stars.domain.repo_starred_by_user?(@grit.id, @defunkt.id)
    refute Stars.domain.repo_starred_by_user?(@github.id, @pj.id)
  end

  test "can't star a private repo she isn't a member of" do
    refute_includes @maddox.starred_repositories, @ambition
    @maddox.star @ambition
    refute_includes @maddox.reload.starred_repositories, @ambition
  end

  test "can't star a repo twice" do
    refute_includes @pj.starred_repositories, @grit
    @pj.star @grit
    assert_includes @pj.reload.starred_repositories, @grit

    assert_no_difference "@grit.reload.stargazer_count" do
      @pj.star @grit
    end
  end

  test "can watch a private repo they are a member of" do
    GitHub.newsies.get_and_update_settings(@pj) do |settings|
      settings.auto_subscribe = true
    end
    refute GitHub.newsies.subscription_status(@pj, @ambition).value.subscribed?
    @ambition.add_member @pj
    assert GitHub.newsies.subscription_status(@pj, @ambition).value.subscribed?
  end

  test "creates an event when starring a repo" do
    @pj.follow(@defunkt)
    @mojombo.follow(@defunkt)

    GitHub.reset_stratocaster
    perform_enqueued_jobs(only: [ProcessEventJob]) { @defunkt.star(@grit) }

    assert event = GitHub.stratocaster_store.last
    targets = Stratocaster.attributes_class_for(event.event_type).from_event(event).targets

    assert_equal "WatchEvent", event.event_type
    assert_equal @defunkt, event.sender_record
    assert_equal @defunkt.followers_count(viewer: nil), targets.size
  end

  test "starring triggers an instrumentation event" do
    events = subscribe "star.create"

    @defunkt.star @grit

    expected_payload = {
      allowed: false,
      star_id: Star.last.id,
      public_repo: @grit.public?,
      action: :created,
      starred: "mojombo/grit",
      starred_type: "Repository",
      starred_id: @grit.id,
      spammy: false,
      user: @defunkt.login,
      user_id: @defunkt.id,
    }

    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
  end

  test "starring a project twice does not increment its stargazer_count" do
    assert_difference "@github.stargazer_count" do
      @pj.star @github
    end

    assert_no_difference "@github.stargazer_count" do
      @pj.star @github
    end
  end

  test "unstarring a project decrements its stargazer_count" do
    assert @pj.star(@github)

    assert_difference "@github.reload.stargazer_count", -1 do
      @pj.unstar(@github)
    end
  end

  test "spammy users stars are spammy" do
    skip "spamminess checks are not enabled on Enterprise" unless GitHub.spamminess_check_enabled?
    assert @spammer.star(@facebox)
    star = Star.where(
      user_id: @spammer.id,
      starrable_id: @facebox.id,
      starrable_type: "Repository",
    ).first
    assert star.user_hidden?
  end

  test "require a verified email to star" do
    @pj.unstar @grit
    GitHub.stubs(:mandatory_email_verification_enabled?).returns(true)
    @pj.require_email_verification!
    @pj.star @grit
    refute_includes @pj.reload.starred_repositories, @grit
  end if GitHub.email_verification_enabled?

  context "#cached_starred_repository_count_by_language_name" do
    test "returns a hash of counts by language" do
      js_repo = create(:repository, primary_language: @js)
      create(:language, language_name: @js, repository: js_repo)

      ruby_repo = create(:repository, primary_language: @ruby)
      create(:language, language_name: @ruby, repository: ruby_repo)

      ruby_repo2 = create(:repository, primary_language: @ruby)
      create(:language, language_name: @ruby, repository: ruby_repo2)

      assert @user.star(js_repo)
      assert @user.star(ruby_repo)
      assert @user.star(ruby_repo2)

      result = @user.cached_starred_repository_count_by_language_name(viewer: nil)

      assert_equal({ "JavaScript" => 1, "Ruby" => 2 }, result)
    end

    test "only counts the user's public repo stars when viewer is anonymous" do
      private_js_repo = create(:private_repository, primary_language: @js)
      create(:language, language_name: @js, repository: private_js_repo)
      private_js_repo.add_member(@user)

      public_js_repo = create(:repository, primary_language: @js)
      create(:language, language_name: @js, repository: public_js_repo)

      assert @user.star(public_js_repo)
      assert @user.star(private_js_repo)

      result = @user.cached_starred_repository_count_by_language_name(viewer: nil)

      assert_equal({ "JavaScript" => 1 }, result)
    end

    test "counts the user's private and public repo stars when viewer is the user" do
      private_js_repo = create(:private_repository, primary_language: @js)
      create(:language, language_name: @js, repository: private_js_repo)
      private_js_repo.add_member(@user)

      public_js_repo = create(:repository, primary_language: @js)
      create(:language, language_name: @js, repository: public_js_repo)

      assert @user.star(public_js_repo)
      assert @user.star(private_js_repo)

      result = @user.cached_starred_repository_count_by_language_name(viewer: @user)

      assert_equal({ "JavaScript" => 2 }, result)
    end
  end
end
