# typed: true
# frozen_string_literal: true

require "test_helper"

class UserFeatureFlagsTest < GitHub::TestCase
  fixtures do
    @employee   = preview_user
    @site_admin = create(:staff_admin_user)


    @github       = github_org
    @early_access = create :team, organization: @github, name: "early-access"

    # emulate the fact that everyone is an owner on GitHub
    @github.add_admin(@site_admin)
    @github.add_admin(@employee)
    @early_access.add_member @employee

    @security_peep = create(:user)
    @security_org  = create(:organization, admin: @security_peep, login: "GitHubSecurity")
    @security_team = create(:team, organization: @security_org, name: "Matasano")
    @security_org.add_admin(@security_peep)
    @tester = create(:user)
    @security_team.add_member @tester
  end

  setup do
    GitHub::FeatureFlag.team_cache.clear
  end
end

class FeaturesVsEmployeeModeTest < GitHub::TestCase
  fixtures do
    @employee = preview_user
    @opted_out_employee = create(:staff_admin_user)

    @github       = github_org
    @opt_out_team = create :team, organization: @github, name: "staffship-features-optout"

    @github.add_admin(@opted_out_employee)
    @opt_out_team.add_member @opted_out_employee

    Flipper.register(:open_source_mavens) {}
  end

  setup do
    enable_feature_flag(:team_shipped, @employee)
    enable_feature_group(:staff_shipped, :preview_features)
    enable_feature_flag(:team_and_staff_shipped, @employee)
    enable_feature_group(:team_and_staff_shipped, :preview_features)
  end

  test "features are enabled in employee mode for the relevant employees" do
    assert_predicate @employee, :preview_features?
    assert GitHub.flipper[:team_shipped].enabled?(@employee), ":team_shipped should be enabled"
    assert GitHub.flipper[:staff_shipped].enabled?(@employee), ":staff_shipped should be enabled"
    assert GitHub.flipper[:team_and_staff_shipped].enabled?(@employee), ":team_and_staff_shipped should be enabled"
  end

  test "features are disabled in employee mode for opted-out employees" do
    refute_predicate @opted_out_employee, :preview_features?

    refute GitHub.flipper[:team_shipped].enabled?(@opted_out_employee), ":team_shipped should be disabled"
    refute GitHub.flipper[:staff_shipped].enabled?(@opted_out_employee), ":staff_shipped should be disabled"
    refute GitHub.flipper[:team_and_staff_shipped].enabled?(@opted_out_employee), ":team_and_staff_shipped should be disabled"
  end

  # Enterprise doesn't have a way of temporarily disabling employee mode.
  unless GitHub.enterprise?
    test "only staff-shipped features are disabled for employees when employee mode is disabled" do
      @employee.disable_employee_mode
      refute_predicate @employee, :preview_features?
      assert GitHub.flipper[:team_shipped].enabled?(@employee), ":team_shipped should be enabled"
      refute GitHub.flipper[:staff_shipped].enabled?(@employee), ":staff_shipped should not be enabled"
      assert GitHub.flipper[:team_and_staff_shipped].enabled?(@employee), ":team_and_staff_shipped should be enabled"
    end

    test "team-shipped features are enabled when employee mode is disabled if the feature is enabled for N% of actors" do
      @employee.disable_employee_mode
      refute_predicate @employee, :preview_features?
      # Ship the features to the public
      GitHub.flipper[:team_shipped].enable_percentage_of_actors(1)
      GitHub.flipper[:team_and_staff_shipped].enable_percentage_of_actors(1)
      assert GitHub.flipper[:team_shipped].enabled?(@employee), ":team_shipped should be enabled"
      assert GitHub.flipper[:team_shipped].enabled?(@employee), ":team_and_staff_shipped should be enabled"
    end

    test "team-shipped features are enabled when employee mode is disabled if the feature is enabled for N% of calls" do
      @employee.disable_employee_mode
      refute_predicate @employee, :preview_features?
      # Ship the features to the public
      GitHub.flipper[:team_shipped].enable_percentage_of_time(1)
      GitHub.flipper[:team_and_staff_shipped].enable_percentage_of_time(1)
      assert GitHub.flipper[:team_shipped].enabled?(@employee), ":team_shipped should be enabled"
      assert GitHub.flipper[:team_shipped].enabled?(@employee), ":team_and_staff_shipped should be enabled"
    end

    test "team-shipped features are enabled when employee mode is disabled if the feature is enabled for groups other than preview_features" do
      @employee.disable_employee_mode
      refute_predicate @employee, :preview_features?
      # Ship the features to the public
      enable_feature_group(:team_shipped, :open_source_mavens)
      enable_feature_group(:team_and_staff_shipped, :open_source_mavens)
      assert GitHub.flipper[:team_shipped].enabled?(@employee), ":team_shipped should be enabled"
      assert GitHub.flipper[:team_shipped].enabled?(@employee), ":team_and_staff_shipped should be enabled"
    end
  end
end

class PrereleaseBadgeTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @staff = preview_user
    @maintainer = create(:user)
  end

  setup do
    @org = create :organization, login: "maintainers"
    @team = create :team, organization: @org, name: "Early access"
    @team.add_member @maintainer
    GitHub::FeatureFlag.team_cache.clear
  end

  if GitHub.enterprise?
    test "doesn't display badges to staff" do
      refute @staff.prerelease_badges?
    end

    test "doesn't display badges to maintainers" do
      refute @maintainer.prerelease_badges?
    end

    test "doesn't display badges to other users" do
      refute @user.prerelease_badges?
    end
  else
    test "displays badges to staff" do
      assert @staff.prerelease_badges?
    end

    test "displays badges to maintainers" do
      assert @maintainer.prerelease_badges?
    end

    test "doesn't display badges to other users" do
      refute @user.prerelease_badges?
    end
  end
end
