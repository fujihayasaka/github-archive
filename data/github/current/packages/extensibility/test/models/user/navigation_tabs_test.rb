# typed: true
# frozen_string_literal: true

require "test_helper"

class UserNavigationTabsTest < GitHub::TestCase
  fixtures do
    @current_user = create(:user)
    @user = create(:user)
  end

  context "#tabs" do
    test "it returns the essential tabs that are present by default" do
      tabs_builder = User::NavigationTabs.new(@user, current_user: @current_user)

      required_tabs = %w[Overview Repositories Projects Stars]
      actual_tabs = tabs_builder.tabs.map(&:text)

      assert (required_tabs - actual_tabs).empty?
    end

    test "it excludes the Projects tab when disabled for an EMU user on the basic seats plan (Copilot Standlone)", skip_enterprise: true do
      emu_business = create :business, :enterprise_managed
      emu_business.update(seats_plan_type: :basic)
      emu_user = create :emu, business: emu_business

      tabs_builder = User::NavigationTabs.new(emu_user, current_user: emu_user)

      required_tabs = %w[Overview Repositories Stars]
      actual_tabs = tabs_builder.tabs.map(&:text)

      assert (required_tabs - actual_tabs).empty?
      refute actual_tabs.include?("Projects")
    end
  end

  context "#repositories_tab" do
    test "shows correct public + private repo count for viewing own profile" do
      create(:user_metadata, user: @user, repository_count: 1, repository_public_and_private_count: 2)
      tabs_builder = User::NavigationTabs.new(@user, current_user: @user)
      assert_equal tabs_builder.repositories_tab.count, 2
    end

    test "shows correct public repo count for viewing someone else's profile" do
      create(:user_metadata, user: @user, repository_count: 1, repository_public_and_private_count: 2)
      tabs_builder = User::NavigationTabs.new(@user, current_user: @current_user)
      assert_equal tabs_builder.repositories_tab.count, 1
    end
  end

  context "#projects_tab" do
    test "shows correct public project count" do
      create(:user_metadata, user: @user, projects_count: 1)
      tabs_builder = User::NavigationTabs.new(@user, current_user: @user)
      assert_equal tabs_builder.projects_tab.count, 1
    end
  end

  context "#packages_tab" do
    test "shows packages tab when enabled" do
      PackageRegistryHelper.stubs(:show_packages?).returns(true)
      tabs_builder = User::NavigationTabs.new(@user, current_user: @user)

      refute_nil tabs_builder.packages_tab
    end

    test "doesn't show packages tab when disabled" do
      PackageRegistryHelper.stubs(:show_packages?).returns(false)
      tabs_builder = User::NavigationTabs.new(@user, current_user: @user)

      assert_nil tabs_builder.packages_tab
    end

    test "shows public package count when viewing other profile" do
      PackageRegistryHelper.stubs(:show_packages?).returns(true)
      create(:user_metadata, user: @user, packages_count: 2, packages_public_and_private_count: 4)
      tabs_builder = User::NavigationTabs.new(@user, current_user: @current_user)

      assert_equal tabs_builder.packages_tab.count, 2
    end

    test "shows total package count when viewing own profile" do
      PackageRegistryHelper.stubs(:show_packages?).returns(true)
      create(:user_metadata, user: @user, packages_count: 2, packages_public_and_private_count: 4)
      tabs_builder = User::NavigationTabs.new(@user, current_user: @user)

      assert_equal tabs_builder.packages_tab.count, 4
    end
  end

  context "#stars_tab" do
    test "shows correct star count" do
      create(:user_metadata, user: @user, stars_count: 3)
      tabs_builder = User::NavigationTabs.new(@user, current_user: @user)

      assert_equal tabs_builder.stars_tab.count, 3
    end
  end

  context "#sponsoring_tab" do
    if GitHub.sponsors_enabled?
      test "shows sponsoring tab when enabled & has sponsorships" do
        tabs_builder = User::NavigationTabs.new(@user, current_user: @user)
        Profiles::User::LayoutData.any_instance.stubs(:active_and_inactive_sponsoring_count).returns(2)

        refute_nil tabs_builder.sponsoring_tab
      end

      test "shows correct sponsor count when viewing own profile" do
        create(:user_metadata, user: @user, sponsoring_count: 4, sponsoring_public_and_private_count: 6)
        tabs_builder = User::NavigationTabs.new(@user, current_user: @user)

        assert_equal 6, tabs_builder.sponsoring_tab.count
      end

      test "shows correct sponsor count when viewing other profile" do
        create(:user_metadata, user: @user, sponsoring_count: 4, sponsoring_public_and_private_count: 6)
        tabs_builder = User::NavigationTabs.new(@user, current_user: @current_user)

        assert_equal 4, tabs_builder.sponsoring_tab.count
      end

      test "shows sponsoring tab for random viewer when profile user only has an inactive public sponsorship" do
        profile_user = create(:user_metadata, user: @user, inactive_sponsoring_count: 1, inactive_sponsoring_public_and_private_count: 1).user
        random = create(:user)
        tabs_builder = User::NavigationTabs.new(@user, current_user: random)

        assert_equal 0, tabs_builder.sponsoring_tab.count
      end

      test "shows sponsoring tab for profile user when user only has an inactive private sponsorship" do
        profile_user = create(:user_metadata, user: @user, inactive_sponsoring_public_and_private_count: 1).user
        tabs_builder = User::NavigationTabs.new(@user, current_user: @user)

        assert_equal 0, tabs_builder.sponsoring_tab.count
      end

      test "does not show sponsoring tab for random viewer when profile user only has an inactive private sponsorship" do
        profile_user = create(:user_metadata, user: @user, inactive_sponsoring_public_and_private_count: 1).user
        random = create(:user)
        tabs_builder = User::NavigationTabs.new(@user, current_user: random)

        assert_nil tabs_builder.sponsoring_tab
      end
    else
      test "doesn't show sponsoring tab when GitHub Sponsors is disabled" do
        tabs_builder = User::NavigationTabs.new(@user, current_user: @user)
        Profiles::User::LayoutData.any_instance.stubs(:active_and_inactive_sponsoring_count).returns(2)

        assert_nil tabs_builder.sponsoring_tab
      end
    end
  end

  context "#activity_tab" do
    test "doesn't show activity tab for another user profile when public activity is disabled" do
      GitHub.stubs(:conduit_feed_enabled?).returns(true)
      GitHub.flipper[:feed_posts].enable_actor(@user)
      @user.settings.set!(:user_profile_feed_visible, false)

      tabs_builder = User::NavigationTabs.new(@user, current_user: @current_user)
      assert_nil tabs_builder.activity_tab
    end

    test "shows activity tab when enabled" do
      GitHub.stubs(:conduit_feed_enabled?).returns(true)
      GitHub.flipper[:feed_posts].enable_actor(@user)
      tabs_builder = User::NavigationTabs.new(@user, current_user: @user)

      refute_nil tabs_builder.activity_tab
    end
  end
end
