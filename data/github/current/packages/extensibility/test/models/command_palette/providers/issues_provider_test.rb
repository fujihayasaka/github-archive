# typed: true
# frozen_string_literal: true

require "test_helper"

module CommandPalette
  module Providers
    class IssuesProviderTest < GitHub::TestCase
      include GitHub::CommandPaletteTestHelpers

      fixtures do
        setup_search

        @user = create :user
        @org = create :organization
        @repo = create :repository, owner: @user
        @org_repo = create :repository, owner: @org

        @user_issue = create(:issue, repository: @repo, title: "User-scoped issue")
        @org_issue = create(:issue, repository: @org_repo, title: "Org-scoped issue")

        make_searchable(@user_issue, @org_issue)
      end

      test "performs search without scope" do
        provider = build_provider(IssuesProvider, current_user: @user)
        results = provider.search("issue")
        assert_same_elements [provider.issue_result(@org_issue), provider.issue_result(@user_issue)], results
      end

      test "finds issues/PRs you created when there is a scope but the query is blank" do
        provider = build_provider(IssuesProvider, current_user: @user, scope: @org_repo)

        my_issue = create(:issue, user: @user, repository: @org_repo)
        make_searchable my_issue

        assert_equal [provider.issue_result(my_issue)], provider.search("")
      end

      test "searches with scope" do
        provider = build_provider(IssuesProvider, current_user: @user, scope: @org)

        # this search shouldn't return any results with this scope
        assert_empty provider.search("User-scoped")

        # but the @org_issue should exist for this scope
        expected = [provider.issue_result(@org_issue)]
        result = provider.search("Org-scoped")

        assert_same_elements expected, result
      end

      test "doesn't search with issue scope" do
        issue = create(:issue)
        provider = build_provider(IssuesProvider, current_user: @user, scope: issue)

        assert_empty provider.search("issue")
      end

      context "search by number" do
        test "finds issue by number for query leading with number" do
          provider = build_provider(IssuesProvider, current_user: @user, scope: @org_repo)
          number = @org_issue.number

          # create an issue with a title that contains the number to ensure we don't return that as well
          new_issue = create :issue, repository: @org_repo, title: "Ticket ##{number} more text"
          make_searchable new_issue

          expected = [provider.issue_result(@org_issue)]
          results = provider.search("#{number}")

          assert_same_elements expected, results
        end

        test "ignores number in query if not leading" do
          provider = build_provider(IssuesProvider, current_user: @user, scope: @org_repo)
          number = @org_issue.number

          # create an issue with a title that contains the number that should also be returned
          new_issue = create :issue, repository: @org_repo, title: "Ticket ##{number} more text"
          make_searchable new_issue

          expected = [provider.issue_result(@org_issue), provider.issue_result(new_issue)]
          results = provider.search("Ticket #{number}")

          assert_same_elements expected, results
        end

        test "ignores number in query if text follows" do
          provider = build_provider(IssuesProvider, current_user: @user, scope: @org_repo)
          number = @org_issue.number

          # create an issue with a title that contains the number that should also be returned
          new_issue = create :issue, repository: @org_repo, title: "Ticket ##{number} more text"
          make_searchable new_issue

          expected = [provider.issue_result(@org_issue), provider.issue_result(new_issue)]
          results = provider.search("#{number} more text")

          assert_same_elements expected, results
        end

        test "filters by type" do
          pull_request = create(:pull_request, :disable_disk_access, repository: @repo)
          closed_issue = create(:issue, repository: @repo, state: :closed)
          make_searchable(pull_request, closed_issue)
          provider = build_provider(IssuesProvider, current_user: @user)
          results = provider.search("issue")

          assert_equal 3, provider.search("is:issue").length
          assert_equal 1, provider.search("is:pr").length
          assert_equal 3, provider.search("is:open").length
          assert_equal 1, provider.search("is:closed").length
          assert_equal 0, provider.search("is:project").length
        end
      end
    end
  end
end
