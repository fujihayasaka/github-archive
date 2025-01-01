# typed: true
# frozen_string_literal: true

require "test_helper"

module CommandPalette
  module Providers
    class FilesProviderTest < GitHub::TestCase
      include GitHub::CommandPaletteTestHelpers

      self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
      fixtures do
        @user = create(:user, login: "ben")
        @org = create(:business_plus_org, name: "ben-org")
        # The `simple` repository example has two files: 'a' and 'empty_file'
        @repo = create(:repository, name: "some_repo", owner: @org, from_example: :simple)
        @repo_scoped_provider = build_provider(Providers::FilesProvider, current_user: @user, scope: @repo)
      end

      test "element configuration" do
        assert_equal "files", FilesProvider.type
        assert_equal 0, FilesProvider.debounce
        assert_equal 1, FilesProvider.fetch_modes.count
        assert_equal "/", FilesProvider.fetch_modes.first.character
        assert_equal ["repository"], FilesProvider.fetch_modes.first.scope_types
      end

      test "returns empty results list when unscoped" do
        assert_equal FilesProvider::EMPTY_RESULTS, build_provider(Providers::FilesProvider, current_user: @user, scope: nil).search(nil)
      end

      test "returns empty results when scoped to scoped user/org" do
        org = create(:organization)

        assert_equal FilesProvider::EMPTY_RESULTS, build_provider(Providers::FilesProvider, current_user: @user, scope: @user).search(nil)
        assert_equal FilesProvider::EMPTY_RESULTS, build_provider(Providers::FilesProvider, current_user: @user, scope: create(:organization)).search(nil)
      end

      test "returns empty results when scoped to scoped an issue" do
        issue = create(:issue)

        assert_equal FilesProvider::EMPTY_RESULTS, build_provider(Providers::FilesProvider, current_user: @user, scope: issue).search(nil)
      end

      test "returns base_file_path from scoped repository" do
        file_result = @repo_scoped_provider.search(nil).first
        assert_equal "/ben-org/some_repo/blob/master", file_result.base_file_path
      end

      test "returns list of files from scoped repository" do
        file_result = @repo_scoped_provider.search(nil).first
        assert_equal %w[a empty_file], file_result.paths
      end

      test "returns filtered results when user does not meet cap filter requirements" do
        context_with_cap_policies = build_context(current_user: @user, scope: @repo, cap_filter: cap_unauthorizing_filter([@org]))
        provider = FilesProvider.new(context_with_cap_policies)
        results = provider.search(nil)
        filtered_results = provider.filter_results(results)
        assert_equal filtered_results.map(&:action).map(&:type).uniq, [:access_policy]
      end
    end
  end
end
