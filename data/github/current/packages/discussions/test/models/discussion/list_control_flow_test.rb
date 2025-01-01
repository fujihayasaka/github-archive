# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionListControlFlowTest < GitHub::TestCase
  fixtures do
    @repository = create(:repository, has_discussions: true)
    @category, @other_category = @repository.discussion_categories.limit(2)
  end

  context "#redirect_path" do
    test "redirects to vanity url with query" do
      flow = Discussion::ListControlFlow.new(
        params: { category_slug: @category.slug },
        repo: @repository,
        parsed_discussions_query: ["test"],
      )
      params = "?discussions_q=test+category%3A#{@category.name}"
      assert_equal "/#{@repository.nwo}/discussions/categories/#{@category.slug}#{params}", flow.redirect_path
    end

    test "redirects to different category url if changed in query" do
      flow = Discussion::ListControlFlow.new(
        params: { category_slug: @category.slug },
        repo: @repository,
        parsed_discussions_query: [[:category, @other_category.name]],
      )
      assert_equal "/#{@repository.nwo}/discussions/categories/#{@other_category.slug}", flow.redirect_path
    end

    test "returns nil when category slug and matching category in query" do
      flow = Discussion::ListControlFlow.new(
        params: { category_slug: @category.slug },
        repo: @repository,
        parsed_discussions_query: [[:category, @category.name]],
      )
      assert_nil flow.redirect_path
    end

    test "redirects to index with mutliple categories" do
      flow = Discussion::ListControlFlow.new(
        params: { category_slug: @category.slug },
        repo: @repository,
        parsed_discussions_query: [
          [:category, @category.name],
          [:category, @other_category.name]
        ],
      )
      params = "?discussions_q=category%3A#{@category.name}+category%3A#{@other_category.name}"
      assert_equal "/#{@repository.nwo}/discussions#{params}", flow.redirect_path
    end

    test "index request with category redirects to vanity url" do
      flow = Discussion::ListControlFlow.new(
        params: {},
        repo: @repository,
        parsed_discussions_query: [[:category, @category.name]],
      )
      assert_equal "/#{@repository.nwo}/discussions/categories/#{@category.slug}", flow.redirect_path
    end

    test "returns nil when no category is in params or query" do
      flow = Discussion::ListControlFlow.new(
        params: {},
        repo: @repository,
        parsed_discussions_query: [],
      )
      assert_nil flow.redirect_path
    end

    test "returns nil when no category is in params or but multiple in query" do
      flow = Discussion::ListControlFlow.new(
        params: {},
        repo: @repository,
        parsed_discussions_query: [
          [:category, @category.name],
          [:category, @other_category.name]
        ],
      )
      assert_nil flow.redirect_path
    end

    test "redirects if author param present" do
      flow = Discussion::ListControlFlow.new(
        params: { author: @repository.owner.login },
        repo: @repository,
        parsed_discussions_query: [],
      )
      params = "?discussions_q=author%3A#{@repository.owner.login}"
      assert_equal "/#{@repository.nwo}/discussions#{params}", flow.redirect_path
    end
  end

  context "#query" do
    test "adds default filter if discussions_q empty" do
      flow = Discussion::ListControlFlow.new(
        params: {},
        repo: @repository,
        parsed_discussions_query: [],
      )
      assert_equal [[:is, "open"]], flow.query
    end

    test "if discussions_q has content do not add default filter" do
      flow = Discussion::ListControlFlow.new(
        params: { discussions_q: "category%3A#{@category.name}" },
        repo: @repository,
        parsed_discussions_query: [[:category, @category.name]],
      )
      assert_equal [[:category, @category.name]], flow.query
    end

    test "if discussions_q is blank do not add default filter" do
      flow = Discussion::ListControlFlow.new(
        params: { discussions_q: "" },
        repo: @repository,
        parsed_discussions_query: [],
      )
      assert_equal [], flow.query
    end
  end
end
