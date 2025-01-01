# typed: true
# frozen_string_literal: true

require "test_helper"

class IsKeywordFilterTest < GitHub::TestCase
  fixtures do
    # instantiate a list of all potential item type/state combinations.
    @open_issue   = MemexProject::ItemMetadata.new(content_type: "Issue",       state: "open",   is_draft: false)
    @closed_issue = MemexProject::ItemMetadata.new(content_type: "Issue",       state: "closed", is_draft: false)
    @draft_issue  = MemexProject::ItemMetadata.new(content_type: "DraftIssue",  state: "open",   is_draft: true)
    @open_pr      = MemexProject::ItemMetadata.new(content_type: "PullRequest", state: "open",   is_draft: false)
    @draft_pr     = MemexProject::ItemMetadata.new(content_type: "PullRequest", state: "open",   is_draft: true)
    @merged_pr    = MemexProject::ItemMetadata.new(content_type: "PullRequest", state: "merged", is_draft: false)
    @closed_pr    = MemexProject::ItemMetadata.new(content_type: "PullRequest", state: "closed", is_draft: false)
  end

  test "is:issue" do
    execute_matrix(
      keywords: "issue",
      matrix:  {
        assert: [@open_issue, @closed_issue, @draft_issue],
        refute: [@open_pr, @draft_pr, @merged_pr, @closed_pr]
      }
    )
  end

  test "-is:issue" do
    execute_matrix(
      keywords: "issue",
      negated: true,
      matrix:  {
        refute: [@open_issue, @closed_issue, @draft_issue],
        assert: [@open_pr, @draft_pr, @merged_pr, @closed_pr]
      }
    )
  end

  test "is:pr" do
    execute_matrix(
      keywords: "pr",
      matrix:  {
        refute: [@open_issue, @closed_issue, @draft_issue],
        assert: [@open_pr, @draft_pr, @merged_pr, @closed_pr]
      }
    )
  end

  test "-is:pr" do
    execute_matrix(
      keywords: "pr",
      negated: true,
      matrix:  {
        assert: [@open_issue, @closed_issue, @draft_issue],
        refute: [@open_pr, @draft_pr, @merged_pr, @closed_pr]
      }
    )
  end

  test "is:draft" do
    execute_matrix(
      keywords: "draft",
      matrix:  {
        assert: [@draft_issue, @draft_pr],
        refute: [@open_issue, @closed_issue, @open_pr, @merged_pr, @closed_pr]
      }
    )
  end

  test "-is:draft" do
    execute_matrix(
      keywords: "draft",
      negated: true,
      matrix:  {
        refute: [@draft_issue, @draft_pr],
        assert: [@open_issue, @closed_issue, @open_pr, @merged_pr, @closed_pr]
      }
    )
  end

  test "is:open" do
    execute_matrix(
      keywords: "open",
      matrix:  {
        assert: [@open_issue, @open_pr, @draft_issue, @draft_pr],
        refute: [@closed_issue, @merged_pr, @closed_pr]
      }
    )
  end

  test "-is:open" do
    execute_matrix(
      keywords: "open",
      negated: true,
      matrix:  {
        refute: [@open_issue, @open_pr, @draft_issue, @draft_pr],
        assert: [@closed_issue, @merged_pr, @closed_pr]
      }
    )
  end

  test "is:closed" do
    execute_matrix(
      keywords: "closed",
      matrix:  {
        refute: [@open_issue, @open_pr, @draft_issue, @draft_pr],
        assert: [@closed_issue, @merged_pr, @closed_pr]
      }
    )
  end

  test "-is:closed" do
    execute_matrix(
      keywords: "closed",
      negated: true,
      matrix:  {
        assert: [@open_issue, @open_pr, @draft_issue, @draft_pr],
        refute: [@closed_issue, @merged_pr, @closed_pr]
      }
    )
  end

  test "is:merged" do
    execute_matrix(
      keywords: "merged",
      matrix:  {
        refute: [@open_issue, @open_pr, @draft_issue, @draft_pr, @closed_issue, @closed_pr],
        assert: [@merged_pr]
      }
    )
  end

  test "-is:merged" do
    execute_matrix(
      keywords: "merged",
      negated: true,
      matrix:  {
        assert: [@open_issue, @open_pr, @draft_issue, @draft_pr, @closed_issue, @closed_pr],
        refute: [@merged_pr]
      }
    )
  end

  def execute_matrix(keywords:, matrix:, negated: false)
    filter = MemexProject::IsKeywordFilter.new(keywords: keywords, negated: negated)

    matrix.each do |test_method, items|
      items.each do |item|
        matches = filter.matches?(item)

        send test_method, matches, "test [#{test_method}] for item [`#{item}] was incorrect for filter [#{filter}]"
      end
    end
  end
end
