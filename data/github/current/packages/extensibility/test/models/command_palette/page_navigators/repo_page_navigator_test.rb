# typed: true
# frozen_string_literal: true

require "test_helper"

module CommandPalette
  module PageNavigators
    class RepoPageNavigatorTest < GitHub::TestCase
      include GitHub::CommandPaletteTestHelpers

      def navigator_for(user, scope)
        repo_scoped_context = build_context(current_user: user, scope: scope)
        RepoPageNavigator.new(repo_scoped_context)
      end

      fixtures do
        @user = create(:user)
        @repo = create(:repository)
      end

      setup do
        @repo_scoped_navigator = navigator_for(@user, @repo)
      end

      context "unscoped context" do
        test "returns empty array" do
          navigator = navigator_for(@user, nil)
          assert_predicate navigator.items, :empty?
        end
      end

      context "scoped context" do
        test "returns valid items" do
          @repo_scoped_navigator.items.each do |item|
            assert_result_structure(item)
            assert_equal item.object, @repo
          end
        end

        test "first item is link to the repository" do
          first_item = @repo_scoped_navigator.items.first

          assert_equal @repo.name_with_owner, first_item.title
          assert_equal "pages", first_item.group
          assert_equal "Jump to", first_item.hint
          assert_result_structure(first_item)
        end

        test "has an Issues page" do
          items = @repo_scoped_navigator.items
          assert_includes items.map(&:title), "Issues"
          assert_result_structure(items.find { |item| item.title == "Issues" })
        end

        context "when the repo doesn't have issues" do
          test "does not have a Issues page" do
            @repo.stubs(:has_issues?).returns(false)
            items = @repo_scoped_navigator.items
            refute_includes items.map(&:title), "Issues"
          end
        end

        test "does not have a Discussions page" do
          @repo.stubs(:discussions_active?).returns(false)
          items = @repo_scoped_navigator.items
          refute_includes items.map(&:title), "Discussions"
        end

        context "has discussions" do
          test "has an Discussions page" do
            @repo.stubs(:discussions_active?).returns(true)
            items = @repo_scoped_navigator.items
            assert_includes items.map(&:title), "Discussions"
            assert_result_structure(items.find { |item| item.title == "Discussions" })
          end
        end

        if GitHub.actions_enabled?
          test "has an Actions page" do
            items = @repo_scoped_navigator.items
            assert_includes items.map(&:title), "Actions"
            assert_result_structure(items.find { |item| item.title == "Actions" })
          end

          context "repo has actions disabled" do
            test "does not have an Actions page" do
              @repo.stubs(:actions_disabled?).returns(true)
              items = @repo_scoped_navigator.items
              refute_includes items.map(&:title), "Actions"
            end
          end
        else
          test "does not have an Actions page" do
            GitHub.stubs(:actions_packages_enterprise_setup_pending?).returns(false)
            items = @repo_scoped_navigator.items
            refute_includes items.map(&:title), "Actions"
          end

          test "actions packages enterprise setup pending" do
            GitHub.stubs(:actions_packages_enterprise_setup_pending?).returns(true)
            items = @repo_scoped_navigator.items
            assert_includes items.map(&:title), "Actions"
            assert_result_structure(items.find { |item| item.title == "Actions" })
          end
        end

        if GitHub.merge_queues_enabled?
          test "includes a merge queue result when merge queue is enabled" do
            merge_queue = create(:merge_queue)
            scoped_navigator = navigator_for(@user, merge_queue.repository)

            items = scoped_navigator.items
            assert_includes items.map(&:title), "Merge queue"
            assert_result_structure(items.find { |item| item.title == "Merge queue" })
          end
        end

        test "has an Projects page" do
          items = @repo_scoped_navigator.items
          assert_includes items.map(&:title), "Projects"
          assert_result_structure(items.find { |item| item.title == "Projects" })
        end

        context "when the repo doesn't have Projects" do
          test "does not have a Projects page" do
            @repo.stubs(:repository_projects_enabled?).returns(false)
            items = @repo_scoped_navigator.items
            refute_includes items.map(&:title), "Projects"
          end
        end

        context "when wiki should be shown" do
          test "has an Wiki page" do
            @repo.stubs(:show_wiki?).with(@user).returns(true)

            items = @repo_scoped_navigator.items
            assert_includes items.map(&:title), "Wiki"
            assert_result_structure(items.find { |item| item.title == "Wiki" })
          end

          test "the wiki has pages even though the user cannot edit it" do
            @repo.stubs(:wiki_writable_by?).with(@user).returns(false)
            @repo.stubs(:wiki_has_pages?).returns(true)

            items = @repo_scoped_navigator.items
            assert_includes items.map(&:title), "Wiki"
            assert_result_structure(items.find { |item| item.title == "Wiki" })
          end

          test "the wiki is world writable" do
            @repo.stubs(:wiki_writable_by?).with(@user).returns(false)
            @repo.stubs(:wiki_has_pages?).returns(false)
            @repo.stubs(:world_writable_wiki?).returns(true)

            items = @repo_scoped_navigator.items
            assert_includes items.map(&:title), "Wiki"
            assert_result_structure(items.find { |item| item.title == "Wiki" })
          end
        end

        context "when wiki should not be shown" do
          test "does not have a Wiki page" do
            @repo.stubs(:show_wiki?).with(@user).returns(false)

            items = @repo_scoped_navigator.items
            refute_includes items.map(&:title), "Wiki"
          end

          test "has a wiki page with no content and user cannot edit it" do
            @repo.stubs(:wiki_has_pages?).returns(false)

            items = @repo_scoped_navigator.items
            refute_includes items.map(&:title), "Wiki"
          end
        end

        test "has an Insights page" do
          items = @repo_scoped_navigator.items
          assert_includes items.map(&:title), "Insights"
          assert_result_structure(items.find { |item| item.title == "Insights" })
        end

        context "is an advisory workspace" do
          test "does not have an Insights page" do
            @repo.stubs(:advisory_workspace?).returns(true)

            items = @repo_scoped_navigator.items
            refute_includes items.map(&:title), "Insights"
          end
        end

        context "dependency graph is disabled and plan does not support insights" do
          test "does not have an Insights page" do
            @repo.stubs(:plan_supports?).returns(false)
            GitHub.stubs(:dependency_graph_enabled?).returns(false)

            items = @repo_scoped_navigator.items
            refute_includes items.map(&:title), "Insights"
          end
        end

        context "user doesnt have maintain/admin permissions" do
          test "does not have a Settings page" do
            items = @repo_scoped_navigator.items
            refute_includes items.map(&:title), "Settings"
          end
        end

        context "user has maintain/admin permissions" do
          test "has a Settings page" do
            navigator = navigator_for(@repo.owner, @repo)
            items = navigator.items
            assert_includes items.map(&:title), "Settings"
            assert_result_structure(items.find { |item| item.title == "Settings" })
          end
        end

        context "user has security manager role" do
          context "from a team assignment" do
            test "has a Settings page" do
              test_org = create(:business_organization, admin: @user)
              test_repo = create(:private_repository, owner: test_org)
              test_team = create(:security_manager_team, organization: test_org)

              test_user = create :user
              test_org.add_member test_user

              navigator = navigator_for(test_user, test_repo)
              refute_includes navigator.items.map(&:title), "Settings"

              test_team.add_member test_user
              navigator = navigator_for(test_user, test_repo)
              items = navigator.items
              assert_includes items.map(&:title), "Settings"
              assert_result_structure(items.find { |item| item.title == "Settings" })
            end
          end

          context "from a user role assignment" do
            test "has a Settings page" do
              test_org = create(:business_organization, admin: @user)
              test_repo = create(:private_repository, owner: test_org)

              test_user = create :user
              test_org.add_member test_user

              navigator = navigator_for(test_user, test_repo)
              refute_includes navigator.items.map(&:title), "Settings"

              test_org.grant_org_role(assignee: test_user, role: Role.security_manager_role)
              navigator = navigator_for(test_user, test_repo)
              items = navigator.items
              assert_includes items.map(&:title), "Settings"
              assert_result_structure(items.find { |item| item.title == "Settings" })
            end
          end
        end
      end
    end
  end
end
