# typed: true
# frozen_string_literal: true

require "test_helper"

class ProjectsClassicSunsetTest < GitHub::TestCase
  fixtures do
    @user = create(:verified_user)
  end

  setup do
    GitHub.flipper.disable(ProjectsClassicSunset::SUNSET_UI_FLAG)
    GitHub.flipper.disable(ProjectsClassicSunset::SUNSET_OVERRIDE_FLAG)
  end

  context "#projects_classic_ui_enabled?" do
    test "returns true if entity is nil" do
      assert ProjectsClassicSunset.projects_classic_ui_enabled?(nil)
    end

    test "returns false if projects classic is sunset" do
      GitHub.flipper.enable(ProjectsClassicSunset::SUNSET_UI_FLAG)
      refute ProjectsClassicSunset.projects_classic_ui_enabled?(@user)
    end

    test "returns true if projects classic is sunset and override flag is enabled" do
      GitHub.flipper.enable(ProjectsClassicSunset::SUNSET_UI_FLAG)
      GitHub.flipper.enable(ProjectsClassicSunset::SUNSET_OVERRIDE_FLAG)
      assert ProjectsClassicSunset.projects_classic_ui_enabled?(@user)
    end

    test "returns false if projects classic is sunset for user" do
      @user.enable_feature(ProjectsClassicSunset::SUNSET_UI_FLAG)
      refute ProjectsClassicSunset.projects_classic_ui_enabled?(@user)
    end

    test "returns true if projects classic is sunset and override flag is enabled for user" do
      @user.disable_feature(ProjectsClassicSunset::SUNSET_UI_FLAG)
      GitHub.flipper.enable(ProjectsClassicSunset::SUNSET_OVERRIDE_FLAG)
      assert ProjectsClassicSunset.projects_classic_ui_enabled?(@user)
    end

    test "returns true if projects classic is not sunset" do
      assert ProjectsClassicSunset.projects_classic_ui_enabled?(@user)
    end

    test "returns true if sunset but user is member of a specific customer org" do
      GitHub.flipper.enable(ProjectsClassicSunset::SUNSET_UI_FLAG)

      rando = create(:verified_user)
      admin = create(:verified_user)
      member = create(:verified_user)
      org = create(:organization, admin: admin, login: "top-customer")
      org.add_member(member)

      ProjectsClassicSunset.stub_const(:SUNSET_OVERRIDE_ORGANIZATIONS, [org.id]) do
        assert ProjectsClassicSunset.projects_classic_ui_enabled?(admin, org: org)
        assert ProjectsClassicSunset.projects_classic_ui_enabled?(member, org: org)

        refute ProjectsClassicSunset.projects_classic_ui_enabled?(rando, org: org)

        # also returns false if org or user is nil (since nothing else enables it)
        refute ProjectsClassicSunset.projects_classic_ui_enabled?(rando, org: nil)
        refute ProjectsClassicSunset.projects_classic_ui_enabled?(nil, org: org)
        refute ProjectsClassicSunset.projects_classic_ui_enabled?(nil, org: nil)
      end
    end
  end
end
