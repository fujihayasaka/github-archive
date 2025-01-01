# typed: true
# frozen_string_literal: true

require "test_helper"

module CommandPalette
  module Providers
    class DiscussionsProviderTest < GitHub::TestCase
      include GitHub::CommandPaletteTestHelpers

      fixtures do
        @user = create(:user, :verified)
        @org = create(:organization, admin: @user)
        @repo = create(:repository, owner: @user, has_discussions: true)
        @discussion = create(:discussion, user: @user, repository: @repo)
      end

      test "doesn't perform search without scope" do
        expect_no_search
        assert_equal [], build_discussions_provider(nil).search("discussion")
      end

      context "Org/User Scope" do
        test "finds discussion current user created if query is blank" do
          provider = build_discussions_provider(@org)
          expected_query = [[:author, "@me"], [:user, @org.owner.login]]

          expect_search_with(query: expected_query, org_scope: true).returns([@discussion])

          assert_equal [provider.discussion_result(@discussion)], provider.search("")
        end

        test "searches with query on discussions in org" do
          search_text = "first responder process revamp"
          expected_query = [search_text, [:user, @org.owner.login]]
          provider = build_discussions_provider(@org)

          expect_search_with(query: expected_query, org_scope: true).returns([@discussion])

          assert_equal [provider.discussion_result(@discussion)], provider.search(search_text)
        end
      end

      context "Repo Scope" do
        test "finds discussion current user created if query is blank" do
          expected_query = [[:author, "@me"]]
          provider = build_discussions_provider(@repo)

          expect_search_with(query: expected_query).returns([@discussion])

          assert_equal [provider.discussion_result(@discussion)], provider.search("")
        end

        test "searches with query on discussions in repo" do
          expected_query = ["Org repo"]
          provider = build_discussions_provider(@repo)

          expect_search_with(query: expected_query).returns([@discussion])

          expected = [provider.discussion_result(@discussion)]
          result = provider.search("Org repo")

          assert_same_elements expected, result
        end
      end

      context "Issue Scope" do
        test "doesn't perform search" do
          provider = build_discussions_provider(create(:issue))

          expect_no_search
          assert_equal [], provider.search("discussion")
        end
      end

      context "search by number" do
        test "finds discussion by number for query leading with number" do
          new_discussion = create(:discussion, repository: @repo)
          provider = build_discussions_provider(@repo)
          number = new_discussion.number

          expect_no_search
          assert_equal [provider.discussion_result(new_discussion)], provider.search("#{number}")
        end

        test "ignores number in query if not leading" do
          provider = build_discussions_provider(@repo)
          number = @discussion.number
          expected_query = ["Leading text #{number}"]

          expect_search_with(query: expected_query).returns([@discussion])

          expected = [provider.discussion_result(@discussion)]
          results = provider.search("Leading text #{number}")

          assert_same_elements expected, results
        end

        test "ignores number in query if text follows" do
          provider = build_discussions_provider(@repo)
          number = @discussion.number
          expected_query = ["#{number} more text"]

          expect_search_with(query: expected_query).returns([@discussion])

          expected = [provider.discussion_result(@discussion)]
          results = provider.search("#{number} more text")

          assert_same_elements expected, results
        end
      end

      context "is: filter" do
        test "doesn't perform search when is:[^discussion]" do
          provider = build_discussions_provider(@org)

          expect_no_search
          assert_equal [], provider.search("is:pr discussion")
        end

        test "performs search when is:discussion" do
          provider = build_discussions_provider(@org)
          expected_query = [[:is, "discussion"], "discussion", [:user, @org.owner.login]]

          expect_search_with(query: expected_query, org_scope: true).returns([@discussion])

          assert_equal [provider.discussion_result(@discussion)], provider.search("is:discussion discussion")
        end

        test "filters to answered" do
          expected_query = [[:is, "answered"], "discussion", [:user, @org.owner.login]]
          provider = build_discussions_provider(@org)

          expect_search_with(query: expected_query, org_scope: true).returns([@discussion])

          assert_equal [provider.discussion_result(@discussion)], provider.search("is:answered discussion")
        end
      end

      private

      def expect_search_with(query:, org_scope: false)
        parameters = { query: query, current_user: @user }
        parameters[:repo] = @repo unless org_scope

        Discussion::SearchResult.expects(:search)
        .with(has_entries(parameters))
      end

      def expect_no_search
        Discussion::SearchResult.expects(:search).never
      end

      def build_discussions_provider(scope)
        build_provider(DiscussionsProvider, current_user: @user, scope: scope)
      end
    end
  end
end
