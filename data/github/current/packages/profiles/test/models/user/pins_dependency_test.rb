# typed: false
# frozen_string_literal: true

require "test_helper"

class UserPinsDependencyTest < GitHub::TestCase
  include HydroTestHelpers
  include GitHub::DatabaseQueryWarningsTestHelpers

  fixtures do
    @user = create(:user)
    @user_profile = create(:profile, user: @user)
    @staff_admin_user = create(:staff_admin_user)

    @admin = create(:user)
    @org = create :organization, admin: @admin
    @org_profile = @org.create_profile

    @emu = create(:emu) unless GitHub.enterprise?

    @disabled_repo = create(:repository)
    create(:profile_pin, pinned_item: @disabled_repo, profile: @user_profile)
    @disabled_repo.access.disable("size", @staff_admin_user)

    @spammer = create(:user, spammy: true)
    @spammy_repo = create(:repository, owner: @spammer)
    create(:profile_pin, pinned_item: @spammy_repo, profile: @user_profile)

    @normal_repo = create(:repository, owner: @user)
    create(:profile_pin, pinned_item: @normal_repo, profile: @user_profile)

    gist_contents = [{ name: "1", value: "random content" }]
    @gist = GistHelpers.generate(contents: gist_contents, user: @user)
    create(:profile_pin, pinned_item: @gist, profile: @user_profile)

    @spam_gist = GistHelpers.generate(contents: gist_contents, user: @spammer)
    create(:profile_pin, pinned_item: @spam_gist, profile: @user_profile)

    @disabled_gist = GistHelpers.generate(contents: gist_contents, user: @user)
    create(:profile_pin, pinned_item: @disabled_gist, profile: @user_profile)
    @disabled_gist.access.disable("size", @staff_admin_user)
  end

  context "#can_pin_profile_items?" do
    test "true for your own profile" do
      assert @user.can_pin_profile_items?(@user)
    end

    test "false for your own profile if it is enterprised managed", skip_enterprise: true do
      refute @emu.can_pin_profile_items?(@emu)
    end

    test "false for someone else's profile" do
      other_user = create(:user)
      refute @user.can_pin_profile_items?(other_user)
    end

    test "true for an organization you admin" do
      org = create(:organization, admin: @user)
      assert org.can_pin_profile_items?(@user)
    end

    test "false for an organization you just belong to" do
      org = create(:organization)
      org.add_member(@user)
      refute org.can_pin_profile_items?(@user)
    end

    test "false for a random organization" do
      org = create(:organization)
      refute org.can_pin_profile_items?(@user)
    end

    test "false for a bot" do
      bot = create(:bot)
      refute bot.can_pin_profile_items?(@user)
    end
  end

  context "#total_pinned_repositories" do
    test "returns count of pinned repos for user" do
      user = create(:user)
      profile = create(:profile, user: user)
      create(:profile_pin, profile: profile)

      assert_equal 1, user.total_pinned_repositories
    end

    test "returns 0 for user without a profile" do
      user = create(:user)
      assert_equal 0, user.total_pinned_repositories
    end
  end

  context "#async_any_pinnable_items?" do
    test "false when user has only gists and type Repository is given" do
      user = create(:user)
      create(:gist, user: user)
      viewer = create(:user)

      refute user.async_any_pinnable_items?(viewer: viewer, types: ["Repository"]).sync
    end

    test "false when user has only repositories and type Gist is given" do
      user = create(:user)
      create(:repository, owner: user)
      viewer = create(:user)

      refute user.async_any_pinnable_items?(viewer: viewer, types: ["Gist"]).sync
    end

    test "true when user has a repository and type Repository is given" do
      user = create(:user)
      create(:repository, owner: user)
      viewer = create(:user)

      assert user.async_any_pinnable_items?(viewer: viewer, types: ["Repository"]).sync
    end

    test "true when user has a gist and type Gist is given" do
      user = create(:user)
      create(:gist, user: user)
      viewer = create(:user)

      assert user.async_any_pinnable_items?(viewer: viewer, types: ["Gist"]).sync
    end

    test "true for user with a public gist" do
      user = create(:user)
      create(:gist, user: user)
      viewer = create(:user)

      assert user.async_any_pinnable_items?(viewer: viewer).sync
    end

    test "returns true for user with public repos" do
      user = create(:user)
      create(:repository, owner: user)
      assert user.async_any_pinnable_items?.sync
    end

    test "returns true for user with public repo contributions" do
      user = create(:user)
      create(:issue, user: user)
      assert user.async_any_pinnable_items?.sync
    end

    test "returns true for user with public commits in a repo they're associated with" do
      user = create(:user)
      repo = create(:repository)
      create(:commit_contribution, user: user, repository: repo)
      create(:issue, user: user, repository: repo)
      assert user.async_any_pinnable_items?.sync
    end

    test "returns false for user without public repos or contributions" do
      user = create(:user)
      refute user.async_any_pinnable_items?.sync
    end

    test "returns false for large bot account when it has no public repositories" do
      large_bot_user = create(:user)
      create(:issue, user: large_bot_user)
      create(:commit_contribution, user: large_bot_user)
      User::ContributionsDependency.stub_const(:LARGE_BOT_ACCOUNTS, [large_bot_user.id]) do
        refute large_bot_user.async_any_pinnable_items?.sync
      end
    end

    test "returns true for org with public repos" do
      org = create(:organization)
      create(:repository, owner: org)
      assert org.async_any_pinnable_items?.sync
    end

    test "returns false for org without public repos" do
      org = create(:organization)
      refute org.async_any_pinnable_items?.sync
    end

    test "returns true for org with private repo in internal view" do
      org = create(:organization)
      create(:private_repository, owner: org)
      assert org.async_any_pinnable_items?(internal_view: true).sync
    end

    test "returns false for org with private repo in internal view" do
      org = create(:organization)
      create(:private_repository, owner: org)
      refute org.async_any_pinnable_items?(internal_view: false).sync
    end
  end

  context "pinned_repository?" do
    test "true when user profile has pinned given repository" do
      user = create(:user)
      profile = create(:profile, user: user)
      repo = create(:repository, owner: user)
      create(:profile_pin, profile: profile, pinned_item: repo)
      assert user.pinned_repository?(repo)
    end

    test "false when user profile has not pinned given repository" do
      user = create(:user)
      create(:profile, user: user)
      repo = create(:repository, owner: user)
      refute user.pinned_repository?(repo)
    end

    test "true when org profile has pinned given repository" do
      org = create(:organization)
      org_profile = create(:profile, user: org)
      repo = create(:repository, owner: org)
      create(:profile_pin, profile: org_profile, pinned_item: repo)
      assert org.pinned_repository?(repo)
    end

    test "false when org profile has pinned given repository but in different view" do
      org = create(:organization)
      org_profile = create(:profile, user: org)
      repo = create(:repository, owner: org)
      create(:profile_pin, profile: org_profile, pinned_item: repo, internal_view: true)
      refute org.pinned_repository?(repo, internal_view: false)
    end
  end

  context "pinned_gist?" do
    test "true when user profile has pinned given gist" do
      user = create(:user)
      profile = create(:profile, user: user)
      gist = create(:gist, user: user)
      create(:profile_pin, pinned_item: gist, profile: profile)

      assert user.pinned_gist?(gist)
    end

    test "false when user profile has not pinned given gist" do
      user = create(:user)
      create(:profile, user: user)
      gist = create(:gist, user: user)

      refute user.pinned_gist?(gist)
    end
  end

  context "#pinned_items_remaining" do
    test "returns full count for user without any pins" do
      user = create(:user)
      assert_equal ProfilePin::LIMIT_PER_PROFILE, user.pinned_items_remaining
    end

    test "returns full count less count of user's pins" do
      user = create(:user)
      profile = create(:profile, user: user)
      create(:profile_pin, profile: profile)
      create(:profile_pin, :gist, profile: profile)

      assert_equal ProfilePin::LIMIT_PER_PROFILE - 2, user.pinned_items_remaining
    end

    test "returns full count for org without any pins" do
      org = create(:organization)
      assert_equal ProfilePin::LIMIT_PER_PROFILE, org.pinned_items_remaining
    end


    test "returns full count less count of org's pins" do
      org = create(:organization)
      org_profile = org.create_profile
      create(:profile_pin, profile: org_profile)
      create(:profile_pin, profile: org_profile)

      assert_equal ProfilePin::LIMIT_PER_PROFILE - 2, org.pinned_items_remaining
    end

    test "returns full count less count of org's pins in internal view" do
      org = create(:organization)
      org_profile = org.create_profile
      create(:profile_pin, profile: org_profile, internal_view: true)
      create(:profile_pin, profile: org_profile, internal_view: true)

      assert_equal ProfilePin::LIMIT_PER_PROFILE - 2, org.pinned_items_remaining(internal_view: true)
    end

    test "returns full count for org in internal view with only pins in public view" do
      org = create(:organization)
      org_profile = org.create_profile
      create(:profile_pin, profile: org_profile, internal_view: false)
      create(:profile_pin, profile: org_profile, internal_view: false)

      assert_equal ProfilePin::LIMIT_PER_PROFILE, org.pinned_items_remaining(internal_view: true)
    end
  end

  context "#pinned_repositories" do
    test "excludes private repositories" do
      user = create(:user)
      profile = create(:profile, user: user)
      repo = create(:repository, owner: user)
      create(:profile_pin, pinned_item: repo, profile: profile)
      repo.private = true
      repo.save!

      refute_includes user.pinned_repositories, repo
    end

    test "excludes inactive repositories" do
      user = create(:user)
      profile = create(:profile, user: user)
      repo = create(:repository, owner: user)
      create(:profile_pin, pinned_item: repo, profile: profile)
      repo.update_attribute(:active, false)

      refute_includes user.pinned_repositories, repo
    end

    test "includes pinned repository" do
      user = create(:user)
      profile = create(:profile, user: user)
      repo = create(:repository, owner: user)
      create(:profile_pin, pinned_item: repo, profile: profile)

      assert_includes user.pinned_repositories, repo
    end
  end

  context "#pinned_items for a User" do
    test "omits pinned gist when types doesn't include Gist" do
      user = create(:user)
      profile = create(:profile, user: user)
      gist = create(:gist, user: user)
      create(:profile_pin, pinned_item: gist, profile: profile)
      viewer = create(:user)

      refute_includes user.pinned_items(viewer: viewer, types: ["Repository"]), gist
    end

    test "includes pinned gist" do
      user = create(:user)
      profile = create(:profile, user: user)
      gist = create(:gist, user: user)
      create(:profile_pin, pinned_item: gist, profile: profile)
      viewer = create(:user)

      assert_includes user.pinned_items(viewer: viewer), gist
    end

    test "excludes private repositories" do
      user = create(:user)
      profile = create(:profile, user: user)
      repo = create(:repository, owner: user)
      create(:profile_pin, pinned_item: repo, profile: profile)
      repo.private = true
      repo.save!

      refute_includes user.pinned_items, repo
    end

    test "excludes inactive repositories" do
      user = create(:user)
      profile = create(:profile, user: user)
      repo = create(:repository, owner: user)
      create(:profile_pin, pinned_item: repo, profile: profile)
      repo.update_attribute(:active, false)

      refute_includes user.pinned_items, repo
    end

    test "includes pinned repository" do
      user = create(:user)
      profile = create(:profile, user: user)
      repo = create(:repository, owner: user)
      create(:profile_pin, pinned_item: repo, profile: profile)

      assert_includes user.pinned_items, repo
    end

    test "omits pinned repository when types doesn't include Repository" do
      user = create(:user)
      profile = create(:profile, user: user)
      repo = create(:repository, owner: user)
      create(:profile_pin, pinned_item: repo, profile: profile)

      refute_includes user.pinned_items(types: ["Gist"]), repo
    end

    test "sorts pins by their position" do
      user = create(:user)
      profile = create(:profile, user: user)
      repo1 = create(:repository, owner: user)
      repo2 = create(:repository, owner: user)
      gist = create(:gist, user: user)
      create(:profile_pin, pinned_item: repo1, profile: profile, position: 1)
      create(:profile_pin, pinned_item: gist, profile: profile, position: 2)
      create(:profile_pin, pinned_item: repo2, profile: profile, position: 3)

      assert_equal [repo1, gist, repo2], user.pinned_items
    end

    test "filters disabled repos if viewer is not staff admin" do
      items = @user.pinned_items(viewer: @user)
      refute_includes items, @disabled_repo
    end

    test "filters disabled gists if viewer is not staff admin" do
      items = @user.pinned_items(viewer: @user)
      refute_includes items, @disabled_gist
    end

    test "keeps disabled repos if viewer is staff admin" do
      items = @user.pinned_items(viewer: @staff_admin_user)
      assert_includes items, @disabled_repo
    end

    test "keeps disabled gists if viewer is staff admin" do
      items = @user.pinned_items(viewer: @staff_admin_user)
      assert_includes items, @disabled_gist
    end

    if GitHub.spamminess_check_enabled?
      test "filters spam repos if the viewer is not staff or the spammer" do
        items = @user.pinned_items(viewer: @user)
        refute_includes items, @spammy_repo
      end

      test "filters spam gists if the viewer is not staff or the spammer" do
        items = @user.pinned_items(viewer: @user)
        refute_includes items, @spam_gist
      end

      test "keeps spam repos if the viewer is the spammer" do
        items = @user.pinned_items(viewer: @spammer)
        assert_includes items, @spammy_repo
      end

      test "keeps spam gists if the viewer is the spammer" do
        items = @user.pinned_items(viewer: @spammer)
        assert_includes items, @spam_gist
      end

      test "keeps spam repos if the viewer is a staff admin" do
        items = @user.pinned_items(viewer: @staff_admin_user)
        assert_includes items, @spammy_repo
      end

      test "keeps spam gists if the viewer is a staff admin" do
        items = @user.pinned_items(viewer: @staff_admin_user)
        assert_includes items, @spam_gist
      end
    end

    test "keeps non-spam, non-disabled repos for random viewer" do
      items = @user.pinned_items(viewer: create(:user))
      assert_includes items, @normal_repo
    end

    test "keeps non-spam, non-disabled gists for random viewer" do
      items = @user.pinned_items(viewer: create(:user))
      assert_includes items, @gist
    end

    test "keeps non-spam, non-disabled repos for anonymous viewer" do
      items = @user.pinned_items(viewer: nil)
      assert_includes items, @normal_repo
    end

    test "keeps non-spam, non-disabled gists for anonymous viewer" do
      items = @user.pinned_items(viewer: nil)
      assert_includes items, @gist
    end
  end

  context "#pinned_items for an Organization" do
    test "includes pinned repository" do
      repo = create(:repository, owner: @org, name: "my-fancy-pin")
      create(:profile_pin, profile: @org_profile, pinned_item: repo)

      assert_includes @org.pinned_items(viewer: @admin), repo
    end

    test "includes private pinned repository in internal view" do
      repo = create(:private_repository, owner: @org, name: "my-fancy-pin")
      create(:profile_pin, profile: @org_profile, pinned_item: repo, internal_view: true)

      assert_includes @org.pinned_items(viewer: @admin, internal_view: true), repo
    end

    test "does not include private pinned repository in internal view for non-org user" do
      repo = create(:private_repository, owner: @org, name: "my-fancy-pin")
      create(:profile_pin, profile: @org_profile, pinned_item: repo, internal_view: true)

      refute_includes @org.pinned_items(viewer: @user, internal_view: true), repo
    end

    test "excludes inactive repositories" do
      repo = create(:repository, owner: @org, name: "my-fancy-pin")
      create(:profile_pin, pinned_item: repo, profile: @org_profile)
      repo.update_attribute(:active, false)

      refute_includes @org.pinned_items, repo
    end
  end

  context "#pin_item_to_dashboard" do
    test "pins item to dashboard without modifying existing pins" do
      pin1 = create(:user_dashboard_pin, :gist, user: @user, position: 1)
      pin2 = create(:user_dashboard_pin, :issue, user: @user, position: 2)
      item_to_pin = create(:user)

      assert_difference("UserDashboardPin.count") do
        @user.pin_item_to_dashboard(item_to_pin)
      end

      assert_equal [pin1.pinned_item, pin2.pinned_item, item_to_pin], @user.dashboard_pinned_items
    end
  end

  context "#unpin_item_from_dashboard" do
    test "returns nil when item was not pinned for the user to begin with" do
      item_to_unpin = create(:issue)

      assert_no_difference("UserDashboardPin.count") do
        assert_nil @user.unpin_item_from_dashboard(item_to_unpin)
      end
    end

    test "returns true when item was unpinned from the user's dashboard" do
      first_pin = create(:user_dashboard_pin, user: @user, position: 1)
      pin = create(:user_dashboard_pin, user: @user, position: 2)
      other_pin = create(:user_dashboard_pin, user: @user, position: 3)

      assert_difference("UserDashboardPin.count", -1) do
        assert @user.unpin_item_from_dashboard(pin.pinned_item)
      end

      refute UserDashboardPin.exists?(pin.id)
      assert_equal [first_pin.pinned_item, other_pin.pinned_item], @user.dashboard_pinned_items
    end

    test "returns false when item was not unpinned from the user's dashboard" do
      pin = create(:user_dashboard_pin, user: @user)
      UserDashboardPin.any_instance.stubs(:destroy).returns(false)

      assert_no_difference("UserDashboardPin.count") do
        result = @user.unpin_item_from_dashboard(pin.pinned_item)
        refute_nil result, "should not return nil"
        refute result, "should be false-y"
      end
    end
  end

  context "#dashboard_pinned_items" do
    test "omits pinned gist when types doesn't include Gist" do
      user = create(:user)
      gist = create(:gist, user: user)
      create(:user_dashboard_pin, pinned_item: gist, user: user)

      refute_includes user.dashboard_pinned_items(types: ["Repository"]), gist
    end

    test "includes pinned gist" do
      user = create(:user)
      gist = create(:gist, user: user)
      create(:user_dashboard_pin, pinned_item: gist, user: user)

      assert_includes user.dashboard_pinned_items, gist
    end

    test "includes private repositories the viewer can see" do
      user  = create(:user)
      owner = create(:organization)

      repo_private = create(:private_repository, owner: owner)
      repo_private.add_member(user, action: :read)
      create(:user_dashboard_pin, pinned_item: repo_private, user: user)

      assert_includes user.dashboard_pinned_items(viewer: user), repo_private
    end

    test "excludes private repositories the viewer cannot see" do
      user  = create(:user)
      owner = create(:organization)

      repo_private = create(:private_repository, owner: owner)
      create(:user_dashboard_pin, pinned_item: repo_private, user: user)

      refute_includes user.dashboard_pinned_items(viewer: user), repo_private
    end

    test "omits inactive repositories" do
      user = create(:user)
      repo = create(:repository, owner: user)
      create(:user_dashboard_pin, pinned_item: repo, user: user)
      repo.update_attribute(:active, false)

      refute_includes user.dashboard_pinned_items, repo
    end

    test "includes pinned repository" do
      user = create(:user)
      repo = create(:repository, owner: user)
      create(:user_dashboard_pin, pinned_item: repo, user: user)

      assert_includes user.dashboard_pinned_items, repo
    end

    test "includes pinned projects" do
      user = create(:user)
      repo = create(:repository, owner: user)
      org = create(:organization, admin: user)
      user_project = create(:project, owner: user)
      repo_project = create(:project, owner: repo)
      org_project = create(:project, owner: org)

      create(:user_dashboard_pin, pinned_item: repo_project, user: user, position: 1)
      create(:user_dashboard_pin, pinned_item: user_project, user: user, position: 2)
      create(:user_dashboard_pin, pinned_item: org_project, user: user, position: 3)

      pinned_items = user.dashboard_pinned_items
      assert_includes pinned_items, repo_project
      assert_includes pinned_items, user_project
      assert_includes pinned_items, org_project
    end

    test "omits pinned repository when types doesn't include Repository" do
      user = create(:user)
      repo = create(:repository, owner: user)
      create(:user_dashboard_pin, pinned_item: repo, user: user)

      refute_includes user.dashboard_pinned_items(types: ["Gist"]), repo
    end

    test "sorts pins by their position" do
      user = create(:user)
      repo1 = create(:repository, owner: user)
      repo2 = create(:repository, owner: user)
      gist = create(:gist, user: user)
      create(:user_dashboard_pin, pinned_item: repo1, user: user, position: 1)
      create(:user_dashboard_pin, pinned_item: gist, user: user, position: 2)
      create(:user_dashboard_pin, pinned_item: repo2, user: user, position: 3)

      assert_equal [repo1, gist, repo2], user.dashboard_pinned_items
    end

    test "omits disabled repos" do
      user = create(:user)
      disabled_repo = create(:repository, owner: user)
      create(:user_dashboard_pin, pinned_item: disabled_repo, user: user)
      disabled_repo.access.disable("size", @staff_admin_user)

      items = user.dashboard_pinned_items
      refute_includes items, disabled_repo
    end

    test "omits disabled gists" do
      user = create(:user)
      disabled_gist = GistHelpers.generate(contents: [{ name: "1", value: "random content" }], user: @user)
      create(:user_dashboard_pin, pinned_item: disabled_gist, user: user)
      disabled_gist.access.disable("size", @staff_admin_user)

      items = user.dashboard_pinned_items
      refute_includes items, disabled_gist
    end

    test "filters out excluded orgs" do
      user = create(:user)
      org = create(:organization, admin: user)
      repo = create(:repository, owner: org)
      issue = create(:issue, repository: repo)
      pull = create(:pull_request, :disable_disk_access, repository: repo)
      team = create(:team, organization: org)
      team.add_member(user)

      create(:user_dashboard_pin, user: user, pinned_item: repo, position: 1)
      create(:user_dashboard_pin, user: user, pinned_item: org, position: 2)
      create(:user_dashboard_pin, user: user, pinned_item: issue, position: 3)
      create(:user_dashboard_pin, user: user, pinned_item: pull, position: 4)
      create(:user_dashboard_pin, user: user, pinned_item: team, position: 5)

      assert_empty user.dashboard_pinned_items(excluded_account_ids: [org.id])
    end

    test "filters out excluded EMU-owned repositories when IP allow list user-level filtering enabled", skip_enterprise: true do
      emu = create :emu
      emu_business = emu.enterprise_managed_business
      enable_feature_flag(:ip_allowlist_user_level_enforcement, emu_business)
      create :ip_allowlist_entry, owner: emu_business
      emu_business.enable_ip_allowlist actor: emu_business.owners.first
      emu_business.enable_ip_allowlist_user_level_enforcement actor: emu_business.owners.first
      assert_predicate emu_business, :ip_allowlist_user_level_enforcement_enabled?
      other_emu = create :emu, business: emu_business
      emu_repo = create :repository, owner: other_emu
      emu_repo.add_member(emu)
      issue = create :issue, repository: emu_repo
      pull = create :pull_request, :disable_disk_access, repository: emu_repo

      create(:user_dashboard_pin, user: emu, pinned_item: emu_repo, position: 1)
      create(:user_dashboard_pin, user: emu, pinned_item: issue, position: 2)
      create(:user_dashboard_pin, user: emu, pinned_item: pull, position: 3)

      assert_empty emu.dashboard_pinned_items(excluded_account_ids: [other_emu.id])
    end

    if GitHub.spamminess_check_enabled?
      test "keeps spam repos created by the viewer" do
        spammer = create(:user, spammy: true)
        spammy_repo = create(:repository, owner: spammer)
        create(:user_dashboard_pin, pinned_item: spammy_repo, user: spammer)

        items = spammer.dashboard_pinned_items(viewer: spammer)
        assert_includes items, spammy_repo
      end

      test "keeps spam gists created by the viewer" do
        spammer = create(:user, spammy: true)
        spammy_gist = GistHelpers.generate(contents: [{ name: "1", value: "random content" }], user: spammer)
        create(:user_dashboard_pin, pinned_item: spammy_gist, user: spammer)

        items = spammer.dashboard_pinned_items(viewer: spammer)
        assert_includes items, spammy_gist
      end

      test "omits spam repos created by someone other than the viewer" do
        user = create(:user)
        spammer = create(:user, spammy: true)
        spammy_repo = create(:repository, owner: spammer)
        create(:user_dashboard_pin, pinned_item: spammy_repo, user: user)

        items = user.dashboard_pinned_items
        refute_includes items, spammy_repo
      end

      test "omits spam gists created by someone other than the viewer" do
        user = create(:user)
        spammer = create(:user, spammy: true)
        spammy_gist = GistHelpers.generate(contents: [{ name: "1", value: "random content" }], user: spammer)
        create(:user_dashboard_pin, pinned_item: spammy_gist, user: user)

        items = user.dashboard_pinned_items
        refute_includes items, spammy_gist
      end
    end
  end

  context "#dashboard_pinned_items_remaining" do
    test "returns full count for user without any dashboard pins" do
      user = create(:user)
      assert_equal UserDashboardPin::LIMIT_PER_USER_DASHBOARD, user.dashboard_pinned_items_remaining
    end

    test "returns full count less count of user's valid dashboard pins" do
      user = create(:user)
      create(:user_dashboard_pin, user: user)
      create(:user_dashboard_pin, :gist, user: user)

      assert_equal UserDashboardPin::LIMIT_PER_USER_DASHBOARD - 2, user.dashboard_pinned_items_remaining
    end

    test "returns full count without decrementing for no longer valid dashboard pins" do
      user  = create(:user)
      owner = create(:organization)

      repo_private = create(:private_repository, owner: owner)
      create(:user_dashboard_pin, pinned_item: repo_private, user: user)

      assert_equal UserDashboardPin::LIMIT_PER_USER_DASHBOARD, user.dashboard_pinned_items_remaining
    end
  end

  context "#pin_items_to_dashboard" do
    test "creates new dashboard pins" do
      repo = create(:repository, owner: @user)
      gist = create(:gist, user: @user)
      assert_difference("UserDashboardPin.count", 2) do
        @user.pin_items_to_dashboard([repo, gist])
      end
    end

    test "deletes existing pins whose pinned_items were not passed in" do
      repo1 = create(:repository, owner: @user)
      repo2 = create(:repository, owner: @user)
      gist1 = create(:gist, user: @user)
      gist2 = create(:gist, user: @user)
      issue1 = create(:issue, user: @user)
      issue2 = create(:issue, user: @user)

      pin1 = create(:user_dashboard_pin, user: @user, pinned_item: repo1)
      pin2 = create(:user_dashboard_pin, user: @user, pinned_item: repo2)
      pin3 = create(:user_dashboard_pin, user: @user, pinned_item: gist1)
      pin4 = create(:user_dashboard_pin, user: @user, pinned_item: gist2)
      pin5 = create(:user_dashboard_pin, user: @user, pinned_item: issue1)
      pin6 = create(:user_dashboard_pin, user: @user, pinned_item: issue2)

      assert_difference("UserDashboardPin.count", -3) do
        @user.pin_items_to_dashboard([repo1, gist2, issue1])
      end

      pinned_item_ids = @user.dashboard_pins.pluck(:id)

      assert_includes pinned_item_ids, pin1.id
      refute_includes pinned_item_ids, pin2.id
      refute_includes pinned_item_ids, pin3.id
      assert_includes pinned_item_ids, pin4.id
      assert_includes pinned_item_ids, pin5.id
      refute_includes pinned_item_ids, pin6.id
    end

    test "deletes pins with destroyed pinned items" do
      repo1 = create(:repository, owner: @user)
      repo2 = create(:repository, owner: @user)
      pin1 = create(:user_dashboard_pin, user: @user, pinned_item: repo1)
      # this disables any call backs which end up destroying the pin created above,
      # we are trying to recreate a scenario where the repo destroy callbacks are not
      # triggered
      repo1.delete

      @user.pin_items_to_dashboard([repo1, repo2])
      assert_same_elements [repo2.id], @user.dashboard_pins.map(&:pinned_item_id)
    end

    test "does not log an error if an nil object is passed" do
      Failbot.expects(:report!).never
      @user.pin_items_to_dashboard([nil])
    end

    test "handles both creation and deletion at once" do
      repo1 = create(:repository, owner: @user)
      repo2 = create(:repository, owner: @user)
      repo3 = create(:repository, owner: @user)
      gist1 = create(:gist, user: @user)

      pin1 = create(:user_dashboard_pin, user: @user, pinned_item: repo2, position: 2)
      pin2 = create(:user_dashboard_pin, user: @user, pinned_item: repo3, position: 3)

      # Should create two and delete one:
      assert_difference("UserDashboardPin.count") do
        @user.pin_items_to_dashboard([repo1, repo3, gist1])
      end

      new_pin1 = UserDashboardPin.find_by(user_id: @user.id, pinned_item_id: repo1.id,
                                          pinned_item_type: "Repository")
      refute_nil new_pin1, "should have added a new pin for repo that was not pinned before"
      new_pin2 = UserDashboardPin.find_by(user_id: @user.id, pinned_item_id: gist1.id,
                                          pinned_item_type: "Gist")
      refute_nil new_pin2, "should have added a new pin for gist that was not pinned before"
      assert_equal [new_pin1.position, pin2.reload.position, new_pin2.position],
        [new_pin1.position, pin2.reload.position, new_pin2.position].sort,
        "should have new_pin1, then pin2, then new_pin2"
      assert_equal [repo1, repo3, gist1],
        [new_pin1.pinned_item, pin2.pinned_item, new_pin2.pinned_item]
      refute UserDashboardPin.exists?(pin1.id),
        "should have removed pin for repo that was not passed in new pin list"
    end

    test "does not create duplicate positions" do
      repo1 = create(:repository, owner: @user, name: "repo1")
      repo2 = create(:repository, owner: @user, name: "repo2")
      repo3 = create(:repository, owner: @user, name: "repo3")

      pin1 = create(:user_dashboard_pin, user: @user, pinned_item: repo1, position: 1)
      pin2 = create(:user_dashboard_pin, user: @user, pinned_item: repo2, position: 2)

      # Should create one and delete another
      assert_no_difference "UserDashboardPin.count" do
        @user.pin_items_to_dashboard([repo2, repo3])
      end

      refute UserDashboardPin.exists?(pin1.id),
        "should have removed pin for repo that was not given in new list"
      assert_equal 2, pin2.reload.position, "should not change existing pin's position"

      new_pin = UserDashboardPin.find_by(user_id: @user.id, pinned_item_id: repo3.id,
                                         pinned_item_type: "Repository")
      refute_nil new_pin,
        "should have created a new UserDashboardPin for repo in given list"
      assert_equal [pin2.position, new_pin.position],
        [pin2.position, new_pin.position].sort,
        "should be in the order with pin2 first, then new_pin"
    end

    test "will not pin inactive repositories" do
      repo = create(:repository, owner: @user, active: nil)

      assert_no_difference "UserDashboardPin.count" do
        @user.pin_items_to_dashboard([repo])
      end
    end

    test "will pin private repositories the user has access to" do
      private_repo = create(:private_repository)
      private_repo.add_member(@user)

      assert_difference "UserDashboardPin.count" do
        @user.pin_items_to_dashboard([private_repo], viewer: @user)
      end
    end

    test "will not pin private repositories the user does not have access to" do
      private_repo = create(:private_repository)

      assert_no_difference "UserDashboardPin.count" do
        @user.pin_items_to_dashboard([private_repo], viewer: @user)
      end
    end

    test "will pin secret gists" do
      gist = GistHelpers.generate(contents: [{ name: "1", value: "random content" }], user: @user,
                           public: false)

      assert_difference "UserDashboardPin.count" do
        @user.pin_items_to_dashboard([gist])
      end
    end

    test "will not pin disabled repositories" do
      repo1 = create(:repository, owner: @user)
      create(:disabled_access_reason, flagged_item: repo1)
      repo2 = create(:repository, owner: @user, disabled_at: 1.week.ago)

      assert_no_difference "UserDashboardPin.count" do
        @user.pin_items_to_dashboard([repo1, repo2])
      end
    end

    test "will not pin disabled gists" do
      gist2 = create(:gist, user: @user, disabled_at: 1.week.ago)

      assert_no_difference "UserDashboardPin.count" do
        @user.pin_items_to_dashboard([gist2])
      end
    end

    test "will pin issues the user has access to" do
      pub_issue = create(:issue)

      assert_difference "UserDashboardPin.count" do
        @user.pin_items_to_dashboard([pub_issue], viewer: @user)
      end
    end

    test "will not pin issues the user does not have access to" do
      private_repo = create(:private_repository)
      private_issue = create(:issue, repository: private_repo)

      assert_no_difference "UserDashboardPin.count" do
        @user.pin_items_to_dashboard([private_issue], viewer: @user)
      end
    end

    test "will pin pull requests the user has access to" do
      pr = create(:pull_request, :disable_disk_access, user: @user)

      assert_difference "UserDashboardPin.count" do
        @user.pin_items_to_dashboard([pr], viewer: @user)
      end
    end

    test "will not pin pull requests the user does not have access to" do
      private_repository = create(:private_repository, from_example: :simple)
      pr = create(:pull_request, repository: private_repository, base_ref: "master",
        head_ref: "cr-line-endings", user: private_repository.owner)

      assert_no_difference "UserDashboardPin.count" do
        @user.pin_items_to_dashboard([pr], viewer: @user)
      end
    end
  end

  context "#remove_unpinned_items_from_list" do
    test "returns array of all currently pinned items if no items_to_unpin are passed in" do
      repo_pin = create(:user_dashboard_pin, :gist, user: @user)
      gist_pin = create(:user_dashboard_pin, user: @user)

      items = @user.remove_unpinned_items_from_list([], viewer: @user)

      assert_same_elements items, [repo_pin, gist_pin].map(&:pinned_item)
    end

    test "returns array of all currently pinned items if an item that is not currently pinned is passed in" do
      repo_pin = create(:user_dashboard_pin, :gist, user: @user)
      gist_pin = create(:user_dashboard_pin, user: @user)
      unpinned_repo = create(:repository)

      items = @user.remove_unpinned_items_from_list(unpinned_repo, viewer: @user)

      assert_same_elements items, [repo_pin, gist_pin].map(&:pinned_item)
    end

    test "returns all current pins if no items_to_unpin are passed in" do
      repo_pin = create(:user_dashboard_pin, :gist, user: @user)
      gist_pin = create(:user_dashboard_pin, user: @user)

      items = @user.remove_unpinned_items_from_list(repo_pin.pinned_item, viewer: @user)

      assert_same_elements items, [gist_pin].map(&:pinned_item)
    end
  end

  context "#create_user_dashboard_pin" do
    test "creates new pinned repositories" do
      repo = create(:repository, owner: @user)

      assert_difference("@user.dashboard_pins.count") do
        @user.create_user_dashboard_pin(pinned_item_id: repo.id,
          pinned_item_type: :Repository, position: 4)
      end
    end

    test "finds existing dashboard pinned repositories" do
      repo = create(:repository, owner: @user)
      pin_params = { pinned_item_id: repo.id, pinned_item_type: :Repository, position: 4 }
      @user.create_user_dashboard_pin(**pin_params)

      assert_no_difference("UserDashboardPin.count") do
        assert @user.create_user_dashboard_pin(**pin_params),
          "should return true to indicate the pin exists as describes"
      end
    end

    test "logs Hydro event for a user with a repo" do
      GitHub.stubs(:hydro_enabled?).returns(true)
      repo = create(:repository, owner: @user)

      @user.create_user_dashboard_pin(pinned_item_id: repo.id,
        pinned_item_type: :Repository, position: 1)

      message = {
        user: Hydro::EntitySerializer.user(@user),
        position: 1,
        pinned_item_id: repo.id,
        pinned_item_type: "REPOSITORY",
      }
      assert_hydro_published(message, schema: "github.v1.UserDashboardPinCreate")
    end

    test "logs Hydro event for a user with a gist" do
      GitHub.stubs(:hydro_enabled?).returns(true)
      gist = create(:gist, user: @user)

      @user.create_user_dashboard_pin(pinned_item_id: gist.id,
        pinned_item_type: :Gist, position: 1)

      message = {
        user: Hydro::EntitySerializer.user(@user),
        position: 1,
        pinned_item_id: gist.id,
        pinned_item_type: "GIST",
      }
      assert_hydro_published(message, schema: "github.v1.UserDashboardPinCreate")
    end
  end

  context "reorder_dashboard_pinned_items" do
    test "updates position of existing dashboard pinned repos" do
      repo1 = create(:repository, owner: @user)
      repo2 = create(:repository, owner: @user)
      repo3 = create(:repository, owner: @user)

      pin1 = create(:user_dashboard_pin, user: @user, pinned_item: repo1, position: 1)
      pin2 = create(:user_dashboard_pin, user: @user, pinned_item: repo2, position: 2)
      pin3 = create(:user_dashboard_pin, user: @user, pinned_item: repo3, position: 3)

      assert_no_difference("UserDashboardPin.count") do
        @user.reorder_dashboard_pinned_items([repo3, repo1, repo2])
      end

      assert_equal 1, pin3.reload.position
      assert_equal 2, pin1.reload.position
      assert_equal 3, pin2.reload.position
    end

    test "returns false when given repository IDs that aren't pinned" do
      repo = create(:repository, owner: @user)

      assert_no_difference("UserDashboardPin.count") do
        @user.reorder_dashboard_pinned_items([repo])
      end
    end
  end

  context "has_dashboard_pins_for_all_items?" do
    test "true when given same items as are pinned" do
      pin1 = create(:user_dashboard_pin, user: @user, position: 1)
      pin2 = create(:user_dashboard_pin, :gist, user: @user, position: 2)
      assert @user.has_dashboard_pins_for_all_items?([pin1.pinned_item, pin2.pinned_item])
    end

    test "false when given an extra repository" do
      repo = create(:repository, owner: @user)
      refute @user.has_dashboard_pins_for_all_items?([repo])
    end

    test "false when given an extra gist" do
      gist = create(:gist, user: @user)
      refute @user.has_dashboard_pins_for_all_items?([gist])
    end

    test "false when missing a pinned repository" do
      create(:user_dashboard_pin, user: @user)
      refute @user.has_dashboard_pins_for_all_items?([])
    end

    test "false when missing a pinned gist" do
      create(:user_dashboard_pin, :gist, user: @user)
      refute @user.has_dashboard_pins_for_all_items?([])
    end
  end
end
