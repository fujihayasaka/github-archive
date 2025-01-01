# typed: true
# frozen_string_literal: true

require "test_helper"

module CommandPalette
  module Providers
    class JumpToMembersOnlyPrefetchedProviderTest < GitHub::TestCase
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
      end

      def build_provider(current_user: @max, scope: nil, thing: JumpToMembersOnlyPrefetchedProvider)
        super(thing, current_user: current_user, scope: scope)
      end

      def jump_to(object, context: @max_context)
        Result.jump_to(object, context: context)
      end

      context "owners" do
        test "returns current user and any organization they belong to" do
          max_provider = build_provider(current_user: @max)
          ben_provider = build_provider(current_user: @ben)

          expected_for_ben = [
            jump_to(@ben, context: @ben_context),
            jump_to(@github, context: @ben_context)
          ]

          assert_equal [jump_to(@max)], max_provider.search("")
          assert_equal expected_for_ben, ben_provider.search("")
        end
      end

      context "repositories" do
        test "when scoped to organization: returns repositories within org where user has contributed, ordered by most commit contributions" do
          repo2 = create(:private_repository, owner: @github, name: "repo2")
          repo3 = create(:private_repository, owner: @github, name: "repo3")
          create(:commit_contribution, :with_summaries, user: @ben, repository: repo2, commit_count: 10)
          create(:commit_contribution, :with_summaries, user: @ben, repository: @dotcom, commit_count: 100)

          provider = build_provider(current_user: @ben, scope: @github)
          context = build_context(current_user: @ben, scope: @github)
          expected_results = [
            jump_to(@dotcom, context: context),
            jump_to(repo2, context: context),
          ]

          assert_equal expected_results, provider.search("")
        end

        test "when scoped to current_user: returns repositories owned by user, ordered by most commits" do
          repo1 = create(:private_repository, owner: @ben, name: "repo1")
          repo2 = create(:private_repository, owner: @ben, name: "repo2")
          repo3 = create(:private_repository, owner: @ben, name: "repo3")

          create(:commit_contribution, :with_summaries, user: @ben, repository: repo1, commit_count: 10)
          create(:commit_contribution, :with_summaries, user: @ben, repository: repo2, commit_count: 100)

          provider = build_provider(current_user: @ben, scope: @ben)
          context = build_context(current_user: @ben, scope: @ben)
          expected_results = [
            jump_to(repo2, context: context),
            jump_to(repo1, context: context),
            jump_to(repo3, context: context)
          ]

          assert_equal expected_results, provider.search("")
        end

        test "when scoped to another user: returns repositories owned by user where current_user has contributed, ordered by most commits" do
          repo1 = create(:repository, owner: @max, name: "repo1")
          repo2 = create(:private_repository, owner: @max, name: "repo2")
          create(:repository, owner: @max, name: "repo3")

          create(:commit_contribution, :with_summaries, user: @ben, repository: repo1, commit_count: 10)
          create(:commit_contribution, :with_summaries, user: @ben, repository: repo2, commit_count: 100)

          provider = build_provider(current_user: @ben, scope: @max)
          context = build_context(current_user: @ben, scope: @max)
          expected_results = [
            jump_to(repo1, context: context),
          ]

          assert_equal expected_results, provider.search("")
        end

        test "when no scope: returns repositories where current_user has contributed, ordered by most commits" do
          repo1 = create(:repository, owner: @max, name: "repo1")
          repo2 = create(:repository, owner: @ben, name: "repo2")

          create(:commit_contribution, :with_summaries, user: @ben, repository: repo1, commit_count: 10)
          create(:commit_contribution, :with_summaries, user: @ben, repository: repo2, commit_count: 100)
          create(:commit_contribution, :with_summaries, user: @ben, repository: @dotcom, commit_count: 1000)

          provider = build_provider(current_user: @ben)
          context = build_context(current_user: @ben)
          expected_results = [
            jump_to(@ben, context: context),
            jump_to(@github, context: context),
            jump_to(@dotcom, context: context),
            jump_to(repo2, context: context),
            jump_to(repo1, context: context),
          ]

          assert_equal expected_results, provider.search("")
        end

        test "when no scope: handles when CommitContribution contains references to non-existant repositories" do
          repo1 = create(:repository, owner: @max, name: "repo1")
          repo2 = create(:repository, owner: @ben, name: "repo2")

          create(:commit_contribution, :with_summaries, user: @ben, repository: repo1, commit_count: 10)
          create(:commit_contribution, :with_summaries, user: @ben, repository: repo2, commit_count: 100)
          create(:commit_contribution, :with_summaries, user: @ben, repository: @dotcom, commit_count: 1000)

          @dotcom.destroy

          provider = build_provider(current_user: @ben)
          context = build_context(current_user: @ben)
          expected_results = [
            jump_to(@ben, context: context),
            jump_to(@github, context: context),
            jump_to(repo2, context: context),
            jump_to(repo1, context: context),
          ]

          assert_equal expected_results, provider.search("")
        end

        test "when scoped to repository: returns nothing" do
          provider = build_provider(current_user: @ben, scope: @dotcom)
          assert_equal [], provider.search("")
        end

        test "when scoped to issue: returns only owners" do
          issue = create(:issue)
          provider = build_provider(current_user: @ben, scope: issue)
          context = build_context(current_user: @ben)
          expected_results = [
            jump_to(@ben, context: context),
            jump_to(@github, context: context)
          ]
          assert_equal expected_results, provider.search("")
        end
      end
    end
  end
end
