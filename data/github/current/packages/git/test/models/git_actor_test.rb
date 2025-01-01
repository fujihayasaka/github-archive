# typed: true
# frozen_string_literal: true

require "test_helper"

class GitActorValidationsTest < GitHub::TestCase
  include AvatarHelper

  fixtures do
    @repository = create(:repository)
    @repo_owner = @repository.owner

    @viewer  = create(:user)
    @user    = create(:user)
    @spammer = create(:user, spammy: true)
  end

  setup do
    @default_attrs = {
      name:       "Monalisa Octocat",
      email:      "mona@github.com",
      time:       "2014-10-07T09:16:42Z",
      repository: @repository,
    }
  end

  test "can be valid" do
    assert_predicate valid_git_actor, :valid?
  end

  test "name cannot be blank" do
    actor = valid_git_actor(name: "")
    refute_predicate actor, :valid?
    assert_includes actor.errors[:name], "can't be blank"
  end

  test "name cannot contain a newline" do
    actor = valid_git_actor(name: "Mr.\nNewline")
    refute_predicate actor, :valid?
    assert_includes actor.errors[:name], "can't contain a newline character"
  end

  test "name cannot contain angle brackets" do
    actor = valid_git_actor(name: "Mr. < Lefty")
    refute_predicate actor, :valid?
    assert_includes actor.errors[:name], "can't contain '<' or '>'"

    actor = valid_git_actor(name: "Mr. > Righty")
    refute_predicate actor, :valid?
    assert_includes actor.errors[:name], "can't contain '<' or '>'"
  end

  test "email cannot be blank" do
    actor = valid_git_actor(email: "")
    refute_predicate actor, :valid?
    assert_includes actor.errors[:email], "can't be blank"
  end

  test "email cannot contain a newline" do
    actor = valid_git_actor(email: "mona\nlist@github.com")
    refute_predicate actor, :valid?
    assert_includes actor.errors[:email], "can't contain a newline character"
  end

  test "email cannot contain angle brackets" do
    actor = valid_git_actor(email: "left<angle@example.com")
    refute_predicate actor, :valid?
    assert_includes actor.errors[:email], "can't contain '<' or '>'"

    actor = valid_git_actor(email: "right>angle@example.com")
    refute_predicate actor, :valid?
    assert_includes actor.errors[:email], "can't contain '<' or '>'"
  end

  context "#display_email" do
    test "is nil with a nil email" do
      actor = valid_git_actor(email: nil)
      assert_nil actor.display_email
    end

    test "transcodes emails as expected" do
      email = "😆@❤️.com"
      actor = valid_git_actor(email: email.b)
      assert_equal email, actor.display_email
    end
  end

  context "#display_name" do
    test "is nil with a nil name" do
      actor = valid_git_actor(name: nil)
      assert_nil actor.display_name
    end

    test "transcodes names as expected" do
      name = "🐳🎈"
      actor = valid_git_actor(name: name.b)
      assert_equal name, actor.display_name
    end
  end

  context "#async_user" do
    test "with a user" do
      actor = valid_git_actor(email: @user.email)
      assert_equal @user, actor.async_user.sync
    end

    test "with no associated user" do
      actor = valid_git_actor
      assert_nil actor.async_user.sync
    end
  end

  context "#async_visible_user" do
    test "when the user is not spammy or blocked or blocking" do
      actor = valid_git_actor(email: @user.email)
      assert_equal @user, actor.async_visible_user(@viewer).sync
    end

    test "when the user is spammy" do
      actor = valid_git_actor(email: @spammer.email)
      if GitHub.spamminess_check_enabled?
        assert_nil actor.async_visible_user(@viewer).sync
      else
        assert_equal @spammer, actor.async_visible_user(@viewer).sync
      end
    end

    test "when the user is blocked by the repo owner" do
      actor = valid_git_actor(email: @user.email)
      @repository.owner.block(@user)
      if GitHub.user_abuse_mitigation_enabled?
        assert_nil actor.async_visible_user(@viewer).sync
      else
        assert_equal @user, actor.async_visible_user(@viewer).sync
      end
    end
  end

  context "#async_bot" do
    test "with a bot" do
      integration = create(:integration)
      actor = valid_git_actor(email: integration.bot.git_author_email)
      assert_equal integration.bot, actor.async_bot.sync
    end

    test "with no associated bot" do
      actor = valid_git_actor
      assert_nil actor.async_bot.sync
    end
  end

  context "#async_visible_actor" do
    test "with a bot" do
      integration = create(:integration)
      actor = valid_git_actor(email: integration.bot.git_author_email)
      result = actor.async_visible_actor(@viewer).sync

      assert result.bot?
    end

    test "with a user" do
      actor = valid_git_actor(email: @user.email)
      result = actor.async_visible_actor(@viewer).sync

      refute result.bot?
    end
  end

  context "#async_actor" do
    test "with a bot" do
      integration = create(:integration)
      actor = valid_git_actor(email: integration.bot.git_author_email)
      result = actor.async_actor.sync

      assert result.bot?
    end

    test "with a user" do
      actor = valid_git_actor(email: @user.email)
      result = actor.async_actor.sync

      refute result.bot?
    end
  end

  context "#async_avatar_url" do
    test "with a user" do
      actor = valid_git_actor(email: @user.email)
      assert_equal @user.primary_avatar_url(32), actor.async_avatar_url.sync
    end

    test "without a user" do
      actor = valid_git_actor
      url = gravatar_url_for(actor.email, 32, "gravatar-user-420", proxied: true)
      assert_equal url, actor.async_visible_avatar_url(@viewer).sync
    end
  end

  test "#async_visible_avatar_url" do
    actor = valid_git_actor(email: @user.email)
    assert_equal @user.primary_avatar_url(32), actor.async_visible_avatar_url(@viewer).sync

    actor = valid_git_actor(email: @spammer.email)
    if GitHub.spamminess_check_enabled?
      url = gravatar_url_for(actor.email, 32, "gravatar-user-420", proxied: true)
      assert_equal url, actor.async_visible_avatar_url(@viewer).sync
    else
      assert_equal @spammer.primary_avatar_url(32), actor.async_visible_avatar_url(@viewer).sync
    end
  end

  context "#async_commits_path_uri" do
    test "with a valid repository and user" do
      actor = valid_git_actor(email: @user.email)
      expected = "/#{@repository.owner}/#{@repository.name}/commits?author=#{@user.login}"
      assert_equal expected, actor.async_commits_path_uri.sync.to_s
    end

    test "without a repository" do
      actor = valid_git_actor(email: @user.email, repository: nil)
      assert_nil actor.async_commits_path_uri.sync
    end

    test "without a user" do
      assert_nil valid_git_actor.async_commits_path_uri.sync
    end

    test "with a bot" do
      integration = create(:integration)
      actor = valid_git_actor(email: integration.bot.git_author_email)

      expected = "/#{@repository.owner}/#{@repository.name}/commits?author=#{integration.bot.slug}%5Bbot%5D"
      assert_equal expected, actor.async_commits_path_uri.sync.to_s
    end
  end

  context "#async_is_blocked_by_or_blocking_repo_owner?" do
    if GitHub.user_abuse_mitigation_enabled?
      test "returns false if the repo owner is not blocking the user and the user is not blocking the repo owner" do
        actor = valid_git_actor(email: @user.email)
        refute @user.blocked_by?(@repo_owner)
        refute @repo_owner.blocked_by?(@user)

        refute actor.async_is_blocked_by_or_blocking_repo_owner?.sync
      end

      test "returns false if the user is a bot" do
        integration = create(:integration)
        actor = valid_git_actor(email: integration.bot.git_author_email)

        refute actor.async_is_blocked_by_or_blocking_repo_owner?.sync
      end

      test "returns false when there is no associated repository" do
        actor = valid_git_actor(email: @user.email, repository: nil)
        refute actor.async_is_blocked_by_or_blocking_repo_owner?.sync
      end

      test "returns true if the repo owner is blocking the user" do
        actor = valid_git_actor(email: @user.email)
        @user.block(@repo_owner)
        refute @user.blocked_by?(@repo_owner)
        assert @repo_owner.blocked_by?(@user)

        assert actor.async_is_blocked_by_or_blocking_repo_owner?.sync
      end

      test "returns true if the repo owner is blocked by the user" do
        actor = valid_git_actor(email: @user.email)
        @repo_owner.block(@user)
        assert @user.blocked_by?(@repo_owner)
        refute @repo_owner.blocked_by?(@user)

        assert actor.async_is_blocked_by_or_blocking_repo_owner?.sync
      end
    else
      test "returns false if blocking is not enabled" do
        actor = valid_git_actor(email: @user.email)
        refute actor.async_is_blocked_by_or_blocking_repo_owner?.sync
      end
    end
  end

  def valid_git_actor(overrides = {})
    GitActor.new(**@default_attrs.merge(overrides))
  end
end

class EmuGitActorValidationsTest < GitHub::TestCase
  include AvatarHelper

  fixtures do
    @emu_user = create(:emu, login: "mojombo2", email: "profile.email@github.com")

    @enterprise = @emu_user.enterprise_managed_business
    @owner = @enterprise.owners.first

    @member = create(:emu, login: "member", business: @enterprise)

    @org = create(:organization, business: @enterprise, admin: @owner)
    @org.add_member(@member)

    @emu_user_repo = create(:repository, name: "grit", owner: @emu_user)
    @org_repo = create(:repository, owner: @org)

  end

  setup do
    @default_attrs = {
      name:       "Monalisa Octocat",
      email:      "mona@github.com",
      time:       "2014-10-07T09:16:42Z",
      repository: @org_repo,
    }
  end

  context "#async_user" do
    test "git actor email should be same as profile email of emu" do
      refute_equal @emu_user.profile_email, @emu_user.emails.first.email

      actor = valid_git_actor(email: @emu_user.profile_email)
      assert_equal @emu_user, actor.async_user.sync
    end

    test "emu's emails in repo commit should be their profile email (without the shortcode)" do
      refute_equal @emu_user.profile_email, @emu_user.emails.first.email

      actor = valid_git_actor(email: @emu_user.profile_email, repository: @emu_user_repo)
      assert_equal @emu_user, actor.async_user.sync
    end

    test "with no associated user" do
      actor = valid_git_actor
      assert_nil actor.async_user.sync
    end
  end

  def valid_git_actor(overrides = {})
    GitActor.new(**@default_attrs.merge(overrides))
  end
end unless GitHub.single_business_environment?
