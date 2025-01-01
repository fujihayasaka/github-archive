# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/conditional_access/filter_test_helper"
require "test_helpers/dependabot_github_app_helper"

class UsersLoaderTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper
  include DependabotGithubAppHelper
  include AvatarHelpers

  fixtures do
    # dependabot setup
    make_trusted_oauth_apps_owner
    @dependabot = create(:dependabot_integration).bot
  end

  setup do
    reset_dependabot_github_app_memoization

    @user = create(:user)

    @repository = create(:repository)
    @issue = create(:issue)
    @context = Issue::Adapter::Context.new(@issue, @repository, @user, cap_filter: cap_authorizing_filter)

    # current issue reactions
    @reacting_user_1 = create(:user)
    @avatar1 = create_avatar_for @reacting_user_1
    @avatar2 = create_avatar_for @reacting_user_1
    PrimaryAvatar.set @avatar2, @reacting_user_1

    @reacting_user_2 = create(:user)
    @reaction1 = Reaction.react(user: @reacting_user_1, subject_id: @issue.id, subject_type: "Issue", content: "+1")
    @reaction2 = Reaction.react(user: @reacting_user_2, subject_id: @issue.id, subject_type: "Issue", content: "+1")

    loader = Issue::Loader::CurrentIssue.new(@context)
    loader.preload_reactable_attributes
    loader.load

    Issue::Loader::CurrentRepository.load_for(@context)
    Issue::Loader::ReactionGroups.load_for(@context, reaction_groups: @context.issue.reaction_groups)
  end

  test "loading users only executes expected queries" do
    result, queries = log_queries do
      Issue::Loader::Users.load_for(
        @context,
        user_ids: @context.issue.reaction_groups.map(&:user_ids).flatten
      )
    end

    # 1 query for loading all users
    # 1 query for loading all users' profiles (via includes)
    expected_count = 2
    assert_equal expected_count, queries.count

    # adds users_by_id to @context
    assert_includes @context.users_by_id, @reacting_user_1.id
    assert_includes @context.users_by_id, @reacting_user_2.id
  end

  context "bots" do
    test "executes expected queries" do
      integration1 = create(:integration, name: "app")
      bot1 = integration1.bot

      integration2 = create(:integration, name: "app2")
      bot2 = integration2.bot

      result, queries = log_queries do
        Issue::Loader::Users.load_for(
          @context,
          user_ids: [bot1.id, bot2.id, @dependabot.id]
        )
      end

      # 1 for users 0
      # 1 for profiles 1

      expected_count = 2
      assert_equal expected_count, queries.count
    end

    test "is_dependabot? executes no queries" do
      Issue::Loader::Users.load_for(@context, user_ids: [@dependabot.id])
      bot_user = @context.users_by_id[@dependabot.id]

      # simulate user association attachment (happens outside in show_loader)
      integration = Integration.find_by(bot_id: @dependabot.id)
      owner = User.find_by(id: T.must(integration).owner_id)
      GitHub::PrefillAssociations.prefill_associations(bot_user, { integration: :owner }, available_records: [integration, owner])
      Issue::Loader::Users.new(@context).preload_primary_avatars_for_users([bot_user], "users")
      Issue::Loader::Users.preload_bots_for(@context, bots: [bot_user])

      is_dependabot = T.let(nil, T.nilable(T::Boolean))
      result, queries = log_queries do
        is_dependabot = bot_user.is_dependabot?
      end

      assert_equal GitHub.dependabot_enabled?, is_dependabot
      assert_equal 0, queries.count
    end
  end

  context "primary avatars" do
    test "loads for given users" do
      users = []

      2.times do
        user = create(:user)
        avatar1 = create_avatar_for user
        avatar2 = create_avatar_for user
        PrimaryAvatar.set avatar2, user
        users << user
      end

      # setup (load users to @context)
      user_ids = users.map(&:id)
      Issue::Loader::Users.load_for(@context, user_ids: user_ids)

      result, queries = log_queries do
        Issue::Loader::Users.new(@context).preload_primary_avatars_for_users(user_ids.map { |user_id| @context.users_by_id[user_id] }, "users")
      end

      assert_equal 1, queries.count
    end
  end
end
