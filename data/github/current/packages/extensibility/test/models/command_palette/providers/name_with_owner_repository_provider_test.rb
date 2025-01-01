# typed: true
# frozen_string_literal: true

require "test_helper"

module CommandPalette
  module Providers
    class NameWithOwnerRepositoryProviderTest < GitHub::TestCase
      include GitHub::CommandPaletteTestHelpers

      fixtures do
        @max = create(:user, login: "max")
        @rails = create(:organization, login: "rails")
        @github = create(:organization, login: "github")

        @max_repo = create(:repository, owner: @max, name: "some_dot_files")
        @max_private_repo = create(:private_repository, owner: @max, name: "secret")
        @rails_repo = create(:public_repository, owner: @rails, name: "rails")
        @dotcom = create(:private_repository, owner: @github, name: "github")
      end

      test "performs search without scope" do
        provider = build_provider(NameWithOwnerRepositoryProvider, current_user: @max)

        results = provider.search("max/some_dot_files")

        assert_same_elements [@max_repo], results.map(&:object)
      end

      test "returns results only when match is exact" do
        provider = build_provider(NameWithOwnerRepositoryProvider, current_user: @max)

        results = provider.search("max/some_dot_")

        assert_empty results
      end

      test "returns private repos owned by the user" do
        provider = build_provider(NameWithOwnerRepositoryProvider, current_user: @max)

        results = provider.search("max/secret")

        assert_same_elements [@max_private_repo], results.map(&:object)
      end

      test "returns public repos not owned by the user" do
        provider = build_provider(NameWithOwnerRepositoryProvider, current_user: @max)

        results = provider.search("rails/rails")

        assert_same_elements [@rails_repo], results.map(&:object)
      end

      test "doesn't return unrelated private repos" do
        provider = build_provider(NameWithOwnerRepositoryProvider, current_user: @max)

        results = provider.search("github/github")

        assert_empty results
      end
    end
  end
end
