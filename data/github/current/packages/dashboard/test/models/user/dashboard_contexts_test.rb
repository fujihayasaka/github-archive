# typed: true
# frozen_string_literal: true

require "test_helper"

class User::DashboardContextsTest < GitHub::TestCase
  fixtures do
    @user        = create(:user, login: "zebra")
    @org         = create(:organization, login: "blackpink", admin: @user)
    @billing_org = create(:organization, login: "a-cool-org")

    @billing_org.billing.add_manager(@user, actor: @billing_org.admin)
  end

  context "#count" do
    test "returns total count of possible contexts" do
      user_contexts = User::DashboardContexts.new(user: @user)
      assert_equal 3, user_contexts.count
      assert_equal 3, user_contexts.contexts.count
    end

    test "returns total count even if over CONTEXT_ORGS_LIMIT" do
      User::DashboardContexts.stub_const(:CONTEXT_ORGS_LIMIT, 1) do
        user_contexts = User::DashboardContexts.new(user: @user)
        assert_equal 3, user_contexts.count
        assert_equal 2, user_contexts.contexts.count
      end
    end
  end

  context "#contexts" do
    test "returns contexts for a user" do
      user_contexts = User::DashboardContexts.new(user: @user)

      assert_equal 3, user_contexts.contexts.count

      context = user_contexts.contexts.shift
      assert_equal "zebra", context.account.login
      assert_predicate context, :adminable?
      refute_predicate context, :billing_manager?

      context = user_contexts.contexts.shift
      assert_equal "a-cool-org", context.account.login
      refute_predicate context, :adminable?
      assert_predicate context, :billing_manager?

      context = user_contexts.contexts.shift
      assert_equal "blackpink", context.account.login
      assert_predicate context, :adminable?
      refute_predicate context, :billing_manager?
    end

    test "returns org contexts limited by CONTEXT_ORGS_LIMIT" do
      User::DashboardContexts.stub_const(:CONTEXT_ORGS_LIMIT, 1) do
        user_contexts = User::DashboardContexts.new(user: @user)

        assert_equal 2, user_contexts.contexts.count

        context = user_contexts.contexts.shift
        assert_equal "zebra", context.account.login
        assert_predicate context, :adminable?
        refute_predicate context, :billing_manager?

        context = user_contexts.contexts.shift
        assert_equal "a-cool-org", context.account.login
        refute_predicate context, :adminable?
        assert_predicate context, :billing_manager?
      end
    end

    test "returns single context for user without org memberships" do
      user = create(:user)
      user_contexts = User::DashboardContexts.new(user: user)

      assert_equal 1, user_contexts.contexts.count
      context = user_contexts.contexts.first
      assert_equal user.login, context.account.login
      assert_predicate context, :adminable?
      refute_predicate context, :billing_manager?
    end
  end

  context "#switchable?" do
    test "true if user has more than one context" do
      user_contexts = User::DashboardContexts.new(user: @user)

      assert_equal 3, user_contexts.contexts.count
      assert_predicate user_contexts, :switchable?
    end

    test "false if user only has one context" do
      user = create(:user)
      user_contexts = User::DashboardContexts.new(user: user)

      assert_equal 1, user_contexts.contexts.count
      refute_predicate user_contexts, :switchable?
    end
  end
end
