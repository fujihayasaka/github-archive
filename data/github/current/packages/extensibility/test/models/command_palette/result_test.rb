# typed: true
# frozen_string_literal: true

require "test_helper"

module CommandPalette
  class ResultTest < GitHub::TestCase
    include GitHub::CommandPaletteTestHelpers

    self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
    fixtures do
      stub_private_avatar_jwt
      @user = build(:user)
      @half_loaded_result = build_result(
        title: "Half loaded",
        action: Actions::JumpToAction.new(path: urls.search_path(q: "french fries")),
        object: @user
      )
      @fully_loaded_result = build_result(
        title: "Fully loaded",
        priority: 1,
        action: Actions::JumpToAction.new(path: urls.search_path(q: "french fries")),
        object: @user
      )
      @result_instance = @fully_loaded_result

      @user = create(:user)
      @user_profile = create(:profile, name: "Mona", user: @user)
      @context = build_context(current_user: @user)

      @user_expected_result = {
        title: "@#{@user.login} - #{@user.profile_name}",
        match_fields: [@user.login, @user.profile_name],
        typeahead: @user.login,
        scope: ResultScope.new(@user),
        icon: Icons::Avatar.new(url: @user.primary_avatar_url, alt: "@#{@user.login}"),
        action: Actions::JumpToAction.new(path: urls.user_path(@user)),
        group: :users
      }

      @org = create(:organization)
      @org_expected_result = {
        title: @org.login,
        scope: ResultScope.new(@org),
        icon: Icons::Avatar.new(url: @org.primary_avatar_url, alt: "@#{@org.login}"),
        action: Actions::JumpToOrgAction.new(path: urls.user_path(@org)),
        group: :organizations
      }

      @repo = create(:repository)
      @repo_expected_result = {
        title: @repo.name_with_owner,
        scope: ResultScope.new(@repo),
        icon: Icons::Octicon.for(@repo),
        action: Actions::JumpToAction.new(path: urls.repository_path(@repo.owner, @repo)),
        group: :repositories
      }

      @project = create(:project, owner: @user)
      @project_expected_result = {
        title: "#{@project.name} ##{@project.number}",
        subtitle: "in #{@project.owner.name}",
        typeahead: @project.name,
        icon: Icons::Octicon.new(name: "project"),
        action: Actions::JumpToAction.new(path: urls.user_project_path(number: @project.number, user_id: @project.owner.name)),
        group: :projects
      }

      @repo_project = create(:project, owner: @repo)
      @repo_project_expected_result = {
        title: "#{@repo_project.name} ##{@repo_project.number}",
        subtitle: "in #{@repo.nwo}",
        typeahead: @repo_project.name,
        icon: Icons::Octicon.new(name: "project"),
        action: Actions::JumpToAction.new(path: urls.repo_project_path(number: @repo_project.number, repository: @repo, user_id: @repo.owner.name)),
        group: :projects
      }

      @memex = create(:memex_project, owner: @org)
      @memex_expected_result = {
        title: "#{@memex.name} ##{@memex.number}",
        subtitle: "in #{@memex.owner.name}",
        typeahead: @memex.name,
        icon: Icons::Octicon.new(name: "table"),
        action: Actions::JumpToAction.new(path: urls.show_org_memex_path(@memex.owner, @memex.number)),
        group: :memex_projects
      }

      @team = create(:team)
      @team_expected_result = {
        title: @team.name_with_owner,
        icon: Icons::Avatar.new(url: @team.primary_avatar_url(56), alt: @team.name_with_owner),
        action: Actions::JumpToTeamAction.new(path: urls.team_path(@team.owner, @team)),
        group: :teams
      }
    end

    def assert_jump_to_result(result, expected_result, expected_object, priority = 1)
      assert_result_structure(result)
      expected_result_with_priority = {
        priority: priority,
      }.merge(expected_result)
      assert_equal result.to_json, expected_result_with_priority.to_json
      assert_equal result.object, expected_object
    end

    context "#jump_to" do
      context "User" do
        test "with context and default priority" do
          assert_jump_to_result(Result.jump_to(@user, context: @context), @user_expected_result, @user, 2)
        end

        test "with context and setting priority" do
          assert_jump_to_result(Result.jump_to(@user, priority: 100, context: @context), @user_expected_result, @user, 101)
        end
      end

      context "Organization" do
        test "with default priority" do
          assert_jump_to_result(Result.jump_to(@org, context: @context), @org_expected_result, @org, 6)
        end

        test "with setting priority" do
          assert_jump_to_result(Result.jump_to(@org, priority: 100, context: @context), @org_expected_result, @org, 105)
        end
      end

      context "Repository" do
        test "with default priority" do
          assert_jump_to_result(Result.jump_to(@repo, context: @context), @repo_expected_result, @repo)
        end

        test "with setting priority" do
          assert_jump_to_result(Result.jump_to(@repo, context: @context, priority: 100), @repo_expected_result, @repo, 100)
        end
      end

      context "Project not owned by repo" do
        test "with default priority" do
          assert_jump_to_result(Result.jump_to(@project, context: @context), @project_expected_result, @project)
        end

        test "with setting priority" do
          assert_jump_to_result(Result.jump_to(@project, context: @context, priority: 100), @project_expected_result, @project, 100)
        end
      end

      context "Project owned by repo" do
        test "with default priority" do
          assert_jump_to_result(Result.jump_to(@repo_project, context: @context), @repo_project_expected_result, @repo_project)
        end

        test "with setting priority" do
          assert_jump_to_result(Result.jump_to(@repo_project, context: @context, priority: 100), @repo_project_expected_result, @repo_project, 100)
        end
      end

      context "Memex" do
        test "with default priority" do
          assert_jump_to_result(Result.jump_to(@memex, context: @context), @memex_expected_result, @memex)
        end

        test "with setting priority" do
          assert_jump_to_result(Result.jump_to(@memex, context: @context, priority: 100), @memex_expected_result, @memex, 100)
        end
      end

      context "Team" do
        test "with default priority" do
          assert_jump_to_result(Result.jump_to(@team, context: @context), @team_expected_result, @team)
        end

        test "with setting priority" do
          assert_jump_to_result(Result.jump_to(@team, context: @context, priority: 100), @team_expected_result, @team, 100)
        end
      end

      test "hint can be set" do
        result = Result.jump_to(@repo, context: @context)
        result.hint = "Jump to"
        assert_equal result.hint, "Jump to"
      end
    end

    context "validates groups" do
      test "with valid group" do
        result = build_result(
          title: "Result",
          priority: 1,
          action: Actions::JumpToAction.new(path: urls.search_path(q: "french fries")),
          object: @user
        )

        assert_equal result.group, ResultGroups::REGISTERED_GROUPS.first
      end

      test "raises error with invalid group" do
        assert_raises ArgumentError, "group must be one of: #{ResultGroups::REGISTERED_GROUPS.join(", ")} or added to ResultGroups::GROUPS" do
          build_result(
             title: "Result",
             priority: 1,
             action: Actions::JumpToAction.new(path: urls.search_path(q: "french fries")),
             group: "bad_group"
           )
        end
      end
    end

    test "responds to #== (supports equality)" do
      half_loaded_result_clone = @half_loaded_result.clone
      fully_loaded_result_clone = @fully_loaded_result.clone

      assert @half_loaded_result.respond_to?(:==)
      assert @fully_loaded_result.respond_to?(:==)

      assert_equal half_loaded_result_clone, @half_loaded_result
      assert_equal fully_loaded_result_clone, @fully_loaded_result
      refute_equal @half_loaded_result, @fully_loaded_result
    end

    test "responds to #as_json" do
      assert_result_structure(@result_instance)
    end

    context ".link_to" do
      test "defaults to no match fields" do
        link_result = Result.link_to(
          title: "Dashboard",
          icon: "home",
          path: "/dashboard",
          priority: 123,
        )

        assert_equal link_result.priority, 123
        assert_equal link_result.title, "Dashboard"
        assert_equal link_result.icon.name, "home"
        assert_equal link_result.action.path, "/dashboard"
        assert_nil link_result.match_fields
      end

      test "match_fields can be set" do
        link_result = Result.link_to(title: "t", icon: "h", path: "/", match_fields: ["hi"])

        assert_equal link_result.match_fields, ["hi"]
      end
    end

    def assert_access_policy_result(result, title, action_path = "")
      assert_equal result.title, title
      assert_equal result.action.path, action_path
      assert_equal result.priority, 100
      assert_equal result.icon.name, "shield-lock"
      assert_equal result.group, :access_policies
      refute_empty result.match_fields
      refute_nil result.typeahead
    end

    context "#access_policy" do
      test "saml org" do
        assert_access_policy_result(
          Result.access_policy(:saml, @org, "/"),
          "Single sign-on to see results within the #{@org} organization",
          "/orgs/#{@org}/sso?return_to=%2F"
        )
      end

      test "saml enterprise" do
        business = create(:business)
        assert_access_policy_result(
          Result.access_policy(:saml, business, "/"),
          "Single sign-on to see results within the #{business} enterprise",
          "/enterprises/#{business}/sso?return_to=%2F"
        )
      end

      test "ip_allowlist org" do
        assert_access_policy_result(
          Result.access_policy(:ip_allowlist, @org, "/"),
          "Connect from an allowed IP address to see results within the #{@org} organization"
        )
      end

      test "ip_allowlist enterprise" do
        business = create(:business)
        assert_access_policy_result(
          Result.access_policy(:ip_allowlist, business, "/"),
          "Connect from an allowed IP address to see results within the #{business} enterprise"
        )
      end

      test "two_factor org" do
        assert_access_policy_result(
          Result.access_policy(:two_factor, @org, "/"),
          "Enable 2FA to see results within the #{@org} organization",
          "/settings/security"
        )
      end

      test "two_factor enterprise" do
        business = create(:business)
        assert_access_policy_result(
          Result.access_policy(:two_factor, business, "/"),
          "Enable 2FA to see results within the #{business} enterprise",
          "/settings/security"
        )
      end
    end
  end
end
