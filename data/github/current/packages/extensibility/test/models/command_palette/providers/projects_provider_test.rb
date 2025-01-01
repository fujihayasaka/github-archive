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
        @user.disable_feature(ProjectsClassicSunset::SUNSET_UI_FLAG)
        @user.disable_feature(ProjectsClassicSunset::SUNSET_OVERRIDE_FLAG)
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

      context "user scope" do
        test "returns user scoped projects" do
          user_project = create(:project, owner: @user, name: "Questlog")
          make_searchable(user_project, type: "project")

          provider = build_provider(ProjectsProvider, current_user: @user, scope: @user)
          results = provider.search("")

          assert_equal [result_title(user_project)], results.map(&:title)
          assert_equal [:projects], results.map(&:group)
          assert_result_structure(results.first)
        end

        test "returns user scoped memexes" do
          memex_table = create(:memex_project, owner: @user, title: "Table of contents", creator: @user)

          provider = build_provider(ProjectsProvider, current_user: @user, scope: @user)
          results = provider.search("")

          assert_equal [result_title(memex_table)], results.map(&:title)
          assert_equal [:memex_projects], results.map(&:group)
          assert_result_structure(results.first)
        end

        test "query filters results" do
          questlog_project = create(:project, owner: @user, name: "Questlog")
          triage_project = create(:project, owner: @user, name: "Bug triage")
          make_searchable(questlog_project, triage_project, type: "project")

          provider = build_provider(ProjectsProvider, current_user: @user, scope: @user)
          results = provider.search("tri")

          assert_equal [result_title(triage_project)], results.map(&:title)
          assert_result_structure(results.first)
        end

        test "returns nothing when scoped to an issue" do
          issue = create(:issue)
          provider = build_provider(ProjectsProvider, current_user: @user, scope: issue)
          results = provider.search("")

          assert_empty results
        end

        context "repo scope" do
          test "returns repo scoped projects" do
            repo_project = create(:project, owner: @user_repo, name: "Backlog")
            make_searchable(repo_project, type: "project")
            # ensure user project is not returned
            user_project = create(:project, owner: @user, name: "Questlog")

            provider = build_provider(ProjectsProvider, current_user: @user, scope: @user_repo)
            results = provider.search("")

            assert_equal [result_title(repo_project)], results.map(&:title)
            assert_result_structure(results.first)
          end

          test "query filters results" do
            repo_project = create(:project, owner: @user_repo, name: "Backlog")
            user_project = create(:project, owner: @user, name: "Questlog")
            make_searchable(repo_project, user_project, type: "project")

            provider = build_provider(ProjectsProvider, current_user: @user, scope: @user_repo)
            provider.stubs(:project_query).returns([repo_project]) # Actually testing Elasticsearch is producing flakes :(
            results = provider.search("bac")

            assert_equal [result_title(repo_project)], results.map(&:title)
            results.each do |result|
              assert_result_structure(result)
            end
          end
        end
      end

      context "org scope" do
        test "returns org scoped projects" do
          org_project = create(:project, owner: @org, name: "Questlog")
          org_repo_project = create(:project, owner: @org_repo, name: "Backlog")
          make_searchable(org_project, org_repo_project, type: "project")

          provider = build_provider(ProjectsProvider, current_user: @user, scope: @org)
          results = provider.search("")

          assert_same_elements [result_title(org_project), result_title(org_repo_project)], results.map(&:title)
          assert_equal [:projects, :projects], results.map(&:group)
          results.each do |result|
            assert_result_structure(result)
          end
        end

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

          questlog_project = create(:project, owner: @org, name: "Questlog", created_at: now)
          memex_table = create(:memex_project, owner: @org, title: "Trianglar problems", creator: @user, created_at: now + 1.second)
          triage_project = create(:project, owner: @org, name: "Bug triage", created_at: now + 2.seconds)
          make_searchable(questlog_project, triage_project, type: "project")

          provider = build_provider(ProjectsProvider, current_user: @user, scope: @org)
          results = provider.search("")

          expected = [memex_table, triage_project, questlog_project].map { |p| result_title(p) }

          assert_equal expected, results.map(&:title)
          assert_result_structure(results.first)
        end

        test "don't show classic projects when sunset flag is enabled" do
          now = Time.now

          @user.enable_feature(ProjectsClassicSunset::SUNSET_UI_FLAG)
          classic_project = create(:project, owner: @org, name: "Classic Project", created_at: now)
          make_searchable(classic_project, type: "project")

          provider = build_provider(ProjectsProvider, current_user: @user, scope: @org)
          results = provider.search("")

          assert_equal [], results

          ProjectsClassicSunset.stub_const(:SUNSET_OVERRIDE_ORGANIZATIONS, [@org.id]) do
            provider = build_provider(ProjectsProvider, current_user: @user, scope: @org)
            results = provider.search("")

            assert_equal 1, results.length
            project = results.first.object
            assert_equal project.id, classic_project.id
            assert_equal project.name, "Classic Project"
          end
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

          questlog_project = create(:project, owner: @org, name: "Questlog", created_at: now)
          triage_project = create(:project, owner: @org, name: "Bug triage", created_at: now + 1.second)
          memex_table = create(:memex_project, owner: @org, title: "Trianglar problems", creator: @user, created_at: now + 2.seconds)
          make_searchable(questlog_project, triage_project, type: "project")

          provider = build_provider(ProjectsProvider, current_user: @user, scope: @org)
          results = provider.search("tri")

          assert_equal [result_title(memex_table), result_title(triage_project)], results.map(&:title)
          results.each do |result|
            assert_result_structure(result)
          end
        end

        context "repo scope" do
          test "returns repo scoped projects" do
            repo_project = create(:project, owner: @org_repo, name: "Backlog")
            make_searchable(repo_project, type: "project")
            repo_memex = create(:memex_project, :with_linked_repo, owner: @org, title: "Roadmap", creator: @user, repo: @org_repo)

            # ensure org projects are not returned
            org_project = create(:project, owner: @org, name: "Questlog")
            org_memex = create(:memex_project, owner: @org, title: "Table of contents", creator: @user)

            provider = build_provider(ProjectsProvider, current_user: @user, scope: @org_repo)
            results = provider.search("")

            assert_equal [result_title(repo_memex), result_title(repo_project)], results.map(&:title)
            assert_equal [:memex_projects, :projects], results.map(&:group)
            assert_result_structure(results.first)
          end

          test "query filters results" do
            repo_project = create(:project, owner: @org_repo, name: "Backlog")
            org_project = create(:project, owner: @org, name: "Questlog")
            make_searchable(repo_project, org_project, type: "project")

            provider = build_provider(ProjectsProvider, current_user: @user, scope: @org_repo)
            provider.stubs(:project_query).returns([repo_project]) # Actually testing Elasticsearch is producing flakes :(
            results = provider.search("bac")

            assert_equal [result_title(repo_project)], results.map(&:title)
            results.each do |result|
              assert_result_structure(result)
            end
          end
        end
      end

      context "is: filtering" do
        test "returns result when query includes `is:project` or `is:`" do
          user_project = create(:project, owner: @user, name: "Questlog")
          make_searchable(user_project, type: "project")

          provider = build_provider(ProjectsProvider, current_user: @user, scope: @user)
          expected_result = [Result.jump_to(user_project, context: provider.context)]

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
