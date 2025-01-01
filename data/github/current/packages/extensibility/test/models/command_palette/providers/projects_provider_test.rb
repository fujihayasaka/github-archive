# typed: true
# frozen_string_literal: true

require "test_helper"

module CommandPalette
  module Providers
    class ProjectsProviderTest < GitHub::TestCase
      include GitHub::CommandPaletteTestHelpers
      include MemexHelpers

      def result_title(project)
        "#{project.name} ##{project.number}"
      end

      fixtures do
        setup_search
        @user = create(:verified_user, login: "usethis", plan: "medium", email: "user@fake.org")
        @org_member = create(:verified_user)
        @org = create(:organization, plan: "business")
        @org.add_member(@user)
        @org.add_member(@org_member)

        @user_repo = create(:repository, owner: @user)
        @org_repo = create(:repository, owner: @org)

        MemexHelpers.setup_organization_wide_access_for_projects("project_writer")
      end

      setup do
        reset_cache
        disable_feature_flag(ProjectsClassicSunset::SUNSET_OVERRIDE_FLAG, @user)
      end

      teardown_once do
        teardown_search
      end

      test "element configuration" do
        assert_same_elements ["!", "#"], ProjectsProvider.fetch_modes.map(&:character)
        assert_same_elements %w[repository owner], ProjectsProvider.fetch_modes.flat_map(&:scope_types).uniq
      end

      test "doesn't perform search without scope" do
        provider = build_provider(ProjectsProvider, current_user: @user, scope: nil)
        results = provider.search("")
        assert_empty results
      end

      test "user scope does not return classic projects in enterprise", enterprise_only: true do
        user_project = create(:project, owner: @user, name: "Questlog")
        make_searchable(user_project, type: "project")

        provider = build_provider(ProjectsProvider, current_user: @user, scope: @user)
        results = provider.search("")

        assert_equal [], results.map(&:title)
        assert_equal [], results.map(&:group)
      end

      context "user scope", skip_enterprise: true do
        test "returns user scoped memexes" do
          memex_table = create(:memex_project, owner: @user, title: "Table of contents", creator: @user)

          provider = build_provider(ProjectsProvider, current_user: @user, scope: @user)
          results = provider.search("")

          assert_equal [result_title(memex_table)], results.map(&:title)
          assert_equal [:memex_projects], results.map(&:group)
          assert_result_structure(results.first)
        end

        test "returns nothing when scoped to an issue" do
          issue = create(:issue)
          provider = build_provider(ProjectsProvider, current_user: @user, scope: issue)
          results = provider.search("")

          assert_empty results
        end
      end

      test "org scope does not return classic projects in enterprise", enterprise_only: true do
        org_project = create(:project, owner: @org, name: "Questlog")
        org_repo_project = create(:project, owner: @org_repo, name: "Backlog")
        make_searchable(org_project, org_repo_project, type: "project")

        provider = build_provider(ProjectsProvider, current_user: @user, scope: @org)
        results = provider.search("")

        assert_same_elements [], results.map(&:title)
        assert_equal [], results.map(&:group)
      end

      context "org scope", skip_enterprise: true do
        test "returns org scoped memexes" do
          memex_table = create(:memex_project, owner: @org, title: "Table of contents", creator: @user)

          provider = build_provider(ProjectsProvider, current_user: @user, scope: @org)
          results = provider.search("")

          assert_equal [result_title(memex_table)], results.map(&:title)
          assert_equal [:memex_projects], results.map(&:group)
          assert_result_structure(results.first)
        end

        test "preserves sort order, placing memex projects before classic projects" do
          now = Time.now

          memex_table = create(:memex_project, owner: @org, title: "Trianglar problems", creator: @user, created_at: now + 1.second)

          provider = build_provider(ProjectsProvider, current_user: @user, scope: @org)
          results = provider.search("")

          expected = [memex_table].map { |p| result_title(p) }

          assert_equal expected, results.map(&:title)
          assert_result_structure(results.first)
        end

        test "don't show classic projects" do
          now = Time.now

          classic_project = create(:project, owner: @org, name: "Classic Project", created_at: now)
          make_searchable(classic_project, type: "project")

          provider = build_provider(ProjectsProvider, current_user: @user, scope: @org)
          results = provider.search("")

          assert_equal [], results
        end

        context "when Projects 'new' is disabled on an org" do
          test "doesn't show memex results" do
            memex_disable

            create(:memex_project, owner: @org, title: "Table of contents", creator: @user)

            provider = build_provider(ProjectsProvider, current_user: @user, scope: @org)
            results = provider.search("")

            assert_empty results
          end
        end

        test "query filters results" do
          now = Time.now

          memex_table = create(:memex_project, owner: @org, title: "Trianglar problems", creator: @user, created_at: now + 2.seconds)

          provider = build_provider(ProjectsProvider, current_user: @user, scope: @org)
          results = provider.search("tri")

          assert_equal [result_title(memex_table)], results.map(&:title)
          results.each do |result|
            assert_result_structure(result)
          end
        end

        context "repo scope" do
          test "returns repo scoped projects" do
            repo_memex = create(:memex_project, :with_linked_repo, owner: @org, title: "Roadmap", creator: @user, repo: @org_repo)

            # ensure org projects are not returned
            org_project = create(:project, owner: @org, name: "Questlog")
            org_memex = create(:memex_project, owner: @org, title: "Table of contents", creator: @user)

            provider = build_provider(ProjectsProvider, current_user: @user, scope: @org_repo)
            results = provider.search("")

            assert_equal [result_title(repo_memex)], results.map(&:title)
            assert_equal [:memex_projects], results.map(&:group)
            assert_result_structure(results.first)
          end
        end
      end

      context "is: filtering" do
        test "does not return classic project result when query includes `is:project` or `is:`", enterprise_only: true do
          user_project = create(:project, owner: @user, name: "Questlog")
          make_searchable(user_project, type: "project")

          provider = build_provider(ProjectsProvider, current_user: @user, scope: @user)
          expected_result = []

          assert_equal provider.search("is:project"), expected_result
          assert_equal provider.search("is:"), expected_result
        end

        test "returns nothing when query includes `is:<anything but project>`" do
          user_project = create(:project, owner: @user, name: "Questlog")
          make_searchable(user_project, type: "project")

          provider = build_provider(ProjectsProvider, current_user: @user, scope: @user)
          assert_empty provider.search("is:pr")
          assert_empty provider.search("is:issue")
          assert_empty provider.search("is:discussion")
        end
      end

      context "author: filtering" do
        test "returns nothing when query includes `author:<anything>`" do
          user_project = create(:project, owner: @user, name: "Questlog")
          make_searchable(user_project, type: "project")

          provider = build_provider(ProjectsProvider, current_user: @user, scope: @user)
          assert_empty provider.search("author:")
          assert_empty provider.search("author:max")
          assert_empty provider.search("author:david")
        end
      end
    end
  end
end
