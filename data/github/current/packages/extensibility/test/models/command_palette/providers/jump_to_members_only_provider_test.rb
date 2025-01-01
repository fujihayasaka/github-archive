# typed: true
# frozen_string_literal: true

require "test_helper"

module CommandPalette
  module Providers
    class JumpToMembersOnlyProviderTest < GitHub::TestCase
      include GitHub::CommandPaletteTestHelpers

      self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
      fixtures do
        @max = create(:user, login: "max")
        @ben = create(:user, login: "ben")
        @max_context = build_context(current_user: @max)
        @ben_context = build_context(current_user: @ben)

        @rails = create(:organization, login: "rails")
        @github = create(:organization, login: "github")
        @github.add_admin(@ben)

        @max_private_repo = create(:private_repository, owner: @max, name: "secret")
        @rails_repo = create(:public_repository, owner: @rails, name: "rails")
        @dotcom = create(:private_repository, owner: @github, name: "github")

        @github.stub(:searchable?, true) do
          make_searchable(@max, @ben, @rails, @github, @max_private_repo, @rails_repo, @dotcom)
        end
      end

      def build_provider(current_user: @max, scope: nil, thing: JumpToMembersOnlyProvider)
        super(thing, current_user: current_user, scope: scope)
      end

      test "has a factory_identifier" do
        assert_equal :jump_to_members_only, JumpToMembersOnlyProvider.factory_identifier
      end

      def jump_to(object, context: @max_context)
        Result.jump_to(object, context: context)
      end

      context "owners" do
        test "returns current user" do
          provider = build_provider(current_user: @max)

          assert_equal [jump_to(@max)], provider.search("max")
        end

        test "returns organization where current user is a member", skip_enterprise: true do
          skip "this test is currently very flakely and we need to figure out why"

          provider = build_provider(current_user: @ben)
          results = provider.search("github")

          assert_includes results, jump_to(@github, context: @ben_context)
        end

        test "doesn't return other users" do
          provider = build_provider(current_user: @max)
          assert_equal [], build_provider.search("ben")
        end

        test "doesn't return organizations where current user isn't a member" do
          provider = build_provider(current_user: @max)
          assert_equal [], provider.search("github")
        end
      end

      context "repositories" do
        test "returns repositories where current user is a member" do
          provider = build_provider(current_user: @max)

          assert_equal [], provider.search("rails/rails")
          @rails_repo.add_member(@max)
          assert_equal [jump_to(@rails_repo)], provider.search("rails/rails")
        end

        test "returns repositories where current user has contributed" do
          provider = build_provider(current_user: @max)

          assert_equal [], provider.search("rails/rails")
          create(:commit_contribution, :with_summaries, repository: @rails_repo, user: @max)
          assert_equal [jump_to(@rails_repo)], provider.search("rails/rails")
        end

        test "returns repositories that are owned by current_user" do
          provider = build_provider(current_user: @max)

          assert_equal [jump_to(@max_private_repo)], provider.search("max/secret")
        end

        test "returns repositories that belong to owner where current user is a member" do
          provider = build_provider(current_user: @ben)

          assert_equal [jump_to(@dotcom)], provider.search("github/github")
        end
      end
    end
  end
end
