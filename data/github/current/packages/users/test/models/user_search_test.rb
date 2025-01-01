# typed: false
# frozen_string_literal: true

require "test_helper"

class UserSearchTest < GitHub::TestCase
  fixtures do
    unless GitHub.single_business_environment?
      @emu_user = create(:emu, :owner, login: "testuser-emu", email: "testemail@github.localhost")
      @emu_enterprise = @emu_user.enterprise_managed_business
      @emu_organization = create(:organization, business: @emu_enterprise, login: "testorg-emu")
      create(:profile, user: @emu_organization, email: "testemail@github.localhost")

      @non_emu_enterprise = create(:business)
      @non_emu_user = create(:user, login: "testuser-non-emu")
      create(:profile, user: @non_emu_user, email: "testemail@github.localhost")
      @non_emu_enterprise.add_user_accounts([@non_emu_user.id])
      @non_emu_organization = create(:organization, business: @non_emu_enterprise, login: "testorg-non-emu")
      create(:profile, user: @non_emu_organization, email: "testemail@github.localhost")
    end
  end

  setup do
    setup_search
  end

  teardown_once do
    teardown_search
  end

  test "excludes bots" do
    # make_searchable test helper will not index bots,
    # work around that by indexing a user and converting to a bot
    pre_bot = create(:user, login: "pre-bot")
    pre_bot.update!(type: "Bot")
    bot = User.find(pre_bot.id)
    create(:integration, name: "super ci", bot: bot)
    human = create(:user, login: "super-duper")
    org   = create(:organization, login: "super-inc")
    make_searchable(pre_bot, human, org)

    results = User.search("super")
    assert_includes results, human
    refute_includes results, bot
  end

  test "includes organizations, if specified" do
    # make_searchable test helper will not index bots,
    # work around that by indexing a user and converting to a bot
    pre_bot = create(:user, login: "pre-bot")
    pre_bot.update!(type: "Bot")
    bot = User.find(pre_bot.id)
    create(:integration, name: "super ci", bot: bot)
    human = create(:user, login: "super-duper")
    org   = create(:organization, login: "super-inc")
    make_searchable(pre_bot, human, org)

    results = User.search("super", with_orgs: true)
    assert_includes results, human
    assert_includes results, org
    refute_includes results, bot
  end

  test "bots are not searchable" do
    bot   = (create(:integration, name: "super ci")).bot
    human = create(:user, login: "super-duper")
    org   = create(:organization, login: "super-inc")

    refute bot.searchable?
    assert human.searchable?
    assert org.searchable?
  end

  test "limits to org members" do
    org   = create(:organization, login: "super-inc")
    human = create(:user, login: "super-duper")
    non_org_member = create(:user, login: "super-person")

    org.add_member(human)

    make_searchable(human, non_org_member)

    results = User.search("super", org: org, org_member_scope: :all)
    assert_includes results, human
    refute_includes results, non_org_member
  end

  test "does not show suspended users" do
    not_suspended = create(:user, login: "super-duper")
    suspended = create(:suspended_user, login: "super-trooper")
    make_searchable(not_suspended, suspended)

    results = User.search("super", exclude_suspended: true)
    assert_includes results, not_suspended
    refute_includes results, suspended
  end

  # https://github.com/github/github/issues/138904
  # Seach filters out suspended users, but must actually show non-suspended
  # users in their place
  test "does let suspended users drown out non_suspended" do
    not_suspended = create(:user)
    suspended = create_list(:suspended_user, 30)
    make_searchable(not_suspended, *suspended)

    # factoried users have a login that starts with "user-"
    results = User.search("user-", exclude_suspended: true)
    assert_includes results, not_suspended
    refute_includes results, suspended
  end

  test "by default, favored friends (org members) appear at the front of the result set" do
    users = create_list(:user, 10)
    org   = create(:organization, login: "super-inc")
    org.add_member(users[8])
    org.add_member(users[9])
    make_searchable(*users)

    org_members = [users[8], users[9]]

    results = User.search("user-", org: org, friends: org_members)
    assert results.take(2) == org_members
  end

  test "favored friends (org members) appear at the back of the result set, if prepend_friends is false" do
    users = create_list(:user, 10)
    org   = create(:organization, login: "super-inc")
    org.add_member(users[8])
    org.add_member(users[9])
    users.append(create(:user, login: "bob"))
    users.append(create(:user, login: "jane"))
    make_searchable(*users)

    org_members = [users[8], users[9]]

    results = User.search("user-", org: org, friends: org_members, prepend_friends: false)
    assert results.last(2) == org_members
  end

  unless GitHub.single_business_environment?
    test "limits to enterprise managed users in EMU business" do
      assert_predicate @emu_user, :is_enterprise_managed?

      make_searchable(@emu_user, @non_emu_user, @emu_organization)

      results = User.search("test", business: @emu_enterprise)
      assert_includes results, @emu_user
      refute_includes results, @non_emu_user
      refute_includes results, @emu_organization
    end

    test "includes EMU orgs if passed with_orgs" do
      assert_predicate @emu_user, :is_enterprise_managed?
      assert_predicate @emu_organization, :enterprise_managed_user_enabled?

      make_searchable(@emu_user, @non_emu_user, @emu_organization)

      results = User.search("test", business: @emu_enterprise, with_orgs: true)
      assert_includes results, @emu_user
      refute_includes results, @non_emu_user
      assert_includes results, @emu_organization
    end

    test "does not return users from other EMU business" do
      @emu_user_2 = create(:emu, :owner, login: "testuser-emu-2")
      @emu_enterprise_2 = @emu_user_2.enterprise_managed_business

      make_searchable(@emu_user, @non_emu_user, @emu_user_2, @emu_organization)

      results = User.search("test", business: @emu_enterprise_2)
      assert_includes results, @emu_user_2
      refute_includes results, @emu_user
      refute_includes results, @non_emu_user
      refute_includes results, @emu_organization
    end

    test "still exclude emu users if no business or org passed as parameter" do
      make_searchable(@emu_user, @non_emu_user, @non_emu_organization)

      results = User.search("test")
      refute_includes results, @emu_user
      assert_includes results, @non_emu_user
      refute_includes results, @non_emu_organization
    end

    test "limits to enterprise managed users in EMU business with @" do
      assert_predicate @emu_user, :is_enterprise_managed?

      make_searchable(@emu_user, @non_emu_user, @emu_organization)

      results = User.search("testemail@", business: @emu_enterprise)
      assert_includes results, @emu_user
      refute_includes results, @non_emu_user
      refute_includes results, @emu_organization
    end

    test "includes EMU orgs if passed with_orgs with @" do
      assert_predicate @emu_user, :is_enterprise_managed?
      assert_predicate @emu_organization, :enterprise_managed_user_enabled?

      make_searchable(@emu_user, @non_emu_user, @emu_organization)

      results = User.search("testemail@", business: @emu_enterprise, with_orgs: true)
      assert_includes results, @emu_user
      refute_includes results, @non_emu_user
      assert_includes results, @emu_organization
    end

    test "does not return users from other EMU business with @" do
      @emu_enterprise_2 = create(:business, :enterprise_managed)
      create(:business_saml_provider, business: @emu_enterprise_2)
      @emu_user_2 = create(:user, login: "testuser-emu-2")
      create(:profile, user: @emu_user_2, email: "testemail@github.localhost")
      @emu_enterprise_2.add_user_accounts([@emu_user_2.id])

      make_searchable(@emu_user, @non_emu_user, @emu_user_2, @emu_organization)

      results = User.search("testemail@", business: @emu_enterprise_2)
      assert_includes results, @emu_user_2
      refute_includes results, @emu_user
      refute_includes results, @non_emu_user
      refute_includes results, @emu_organization
    end

    test "does not return users from EMU business with @ when searched inside non emu enterprise" do
      make_searchable(@emu_user, @non_emu_user, @non_emu_organization)

      results = User.search("testemail@", business: @non_emu_enterprise)
      refute_includes results, @emu_user
      assert_includes results, @non_emu_user
      refute_includes results, @non_emu_organization
    end

    test "includes non EMU orgs if passed with_orgs with @ when searched inside non emu enterprise" do
      make_searchable(@emu_user, @non_emu_user, @non_emu_organization)

      results = User.search("testemail@", business: @non_emu_enterprise, with_orgs: true)
      refute_includes results, @emu_user
      assert_includes results, @non_emu_user
      assert_includes results, @non_emu_organization
    end
  end
end
