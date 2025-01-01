# typed: true
# frozen_string_literal: true

require "test_helper"

module CommandPalette
  module Providers
    class JumpToProviderTest < GitHub::TestCase
      include GitHub::CommandPaletteTestHelpers

      self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
      fixtures do
        @max = create(:user, login: "max")
        @ben = create(:user, login: "ben")
        @rae = create(:user, login: "rae")
        @context = build_context(current_user: @max)

        @rails = create(:organization, login: "rails")
        @github = create(:organization, login: "github")
        @github.add_admin(@ben)

        @max_repo = create(:repository, owner: @max, name: "some_dot_files")
        @max_private_repo = create(:private_repository, owner: @max, name: "secret")
        @rails_repo = create(:public_repository, owner: @rails, name: "rails")
        @dotcom = create(:private_repository, owner: @github, name: "github")

        @no_scope_provider = build_provider
        @github.stub(:searchable?, true) do
          make_searchable(@max, @ben, @rae, @rails, @github, @max_repo, @max_private_repo, @rails_repo, @dotcom)
        end
      end

      def build_provider(current_user: @max, scope: nil)
        super(JumpToProvider, current_user: current_user, scope: scope)
      end

      test "has a factory_identifier" do
        assert_equal :jump_to, JumpToProvider.factory_identifier
      end



      test "partial matches repos" do
        expected = [@max_private_repo].map { |object| Result.jump_to(object, context: @no_scope_provider.context) }

        assert_same_elements expected, @no_scope_provider.search("max/secr")
        assert_same_elements expected, @no_scope_provider.search("secr")
      end


      test "only shows repositories the user can read" do
        provider = build_provider(current_user: @amy)
        assert_equal [], build_provider.search("github/github")

        provider = build_provider(current_user: @ben)
        assert_equal [Result.jump_to(@dotcom, context: provider.context)], provider.search("github/github")
      end

      test "returns no results when query and scope empty" do
        assert_same_elements [], @no_scope_provider.search("")
      end

      test "returns no results when query empty and scope user" do
        assert_same_elements [], build_provider(scope: @max).search("")
      end

      test "returns no results when scoped to a repository" do
        provider = build_provider(scope: @max_repo)

        assert_equal [], provider.search("")
        assert_equal [], provider.search("github")
        assert_equal [], provider.search("rails")
        assert_equal [], provider.search("max/")
      end

      test "returns no results when scoped to an issue" do
        issue = create(:issue)
        provider = build_provider(scope: issue)

        assert_equal [], provider.search("")
        assert_equal [], provider.search("github")
        assert_equal [], provider.search("rails")
        assert_equal [], provider.search("max/")
      end

      test "only searches for owner's repositories when scoped to owner" do
        provider = build_provider(scope: @max)
        expected = [@max_repo, @max_private_repo].map { |repo| Result.jump_to(repo, context: provider.context) }

        assert_same_elements expected, provider.search("s") # both repo start with "s"
        assert_same_elements [], provider.search("rails")
      end

      test "handles searching for a repo under a user that can't be found" do
        assert_same_elements [], build_provider.search("not_a_real_user/repo")
      end
    end
  end
end
