# typed: true
# frozen_string_literal: true

require "test_helper"

module CommandPalette
  module Providers
    class RecentIssuesProviderTest < GitHub::TestCase
      include GitHub::CommandPaletteTestHelpers

      fixtures do
        @user = create(:user, login: "max")
      end

      test "element configuration" do
        assert_equal "prefetched", RecentIssuesProvider.type
        assert_equal 0, RecentIssuesProvider.debounce
        assert_equal 2, RecentIssuesProvider.fetch_modes.count
        RecentIssuesProvider.fetch_modes.each do |mode|
          assert_equal "#", mode.character
        end
      end

      test "returns issue user created" do
        issue = create(:issue, user: @user)
        other_issue = create(:issue)

        provider = build_provider(RecentIssuesProvider, current_user: @user)
        assert_equal [provider.issue_result(issue)], provider.search("")
      end

      test "returns pull request created by user" do
        pull_request = create(
          :pull_request,
          :disable_disk_access,
          user: @user,
          issue: create(:issue, user: @user)
        )

        provider = build_provider(RecentIssuesProvider, current_user: @user)
        assert_equal [provider.issue_result(pull_request.issue)], provider.search("")
      end

      test "filters by context.owner" do
        repo = create(:repository, owner: @user)
        repo_issue = create(:issue, repository: repo, user: @user)
        other_issue = create(:issue, user: @user)

        provider = build_provider(RecentIssuesProvider, current_user: @user, scope: @user)
        assert_equal [provider.issue_result(repo_issue)], provider.search("")

        provider = build_provider(RecentIssuesProvider, current_user: @user, scope: repo)
        assert_equal [provider.issue_result(repo_issue)], provider.search("")
      end

      test "filters out issues outside repository scope" do
        repo1 = create(:repository, owner: @user)
        repo2 = create(:repository, owner: @user)
        repo1_issue = create(:issue, repository: repo1, user: @user)
        repo2_issue = create(:issue, repository: repo2, user: @user)

        provider = build_provider(RecentIssuesProvider, current_user: @user, scope: repo1)
        assert_equal [provider.issue_result(repo1_issue)], provider.search("")
      end

      test "filters out issues outside repository scope when scoped to an issue" do
        repo1 = create(:repository, owner: @user)
        repo2 = create(:repository, owner: @user)
        repo1_issue = create(:issue, repository: repo1, user: @user)
        repo2_issue = create(:issue, repository: repo2, user: @user)

        provider = build_provider(RecentIssuesProvider, current_user: @user, scope: repo1_issue)
        assert_equal [provider.issue_result(repo1_issue)], provider.search("")
      end
    end
  end
end
