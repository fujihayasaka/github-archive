# typed: true
# frozen_string_literal: true

require "test_helper"

class Forks::ForkDetailComponentTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers

  fixtures do
    @repo = create(:repository, owner: create(:user))
  end

  def assert_repo_link_with_count(path, count)
    assert_selector "a[href^='/#{@repo.name_with_display_owner}/#{path}']", text: count
  end

  def attributes
    @attributes ||= {
        stargazer_counts: { @repo.id => 42 },
        open_pull_request_counts: { @repo.id => 13 },
        open_issue_counts: { @repo.id => 7 },
        child_fork_counts: { @repo.id => 3 },
        last_updated: { @repo.id => @repo.pushed_at },
      }
  end

  context "render" do
    test "it renders correctly" do
      render_inline(Forks::ForkDetailComponent.new(@repo, attributes), allowed_queries: 1)
      assert_repo_link_with_count("stargazers", 42)
      assert_repo_link_with_count("pulls", 13)
      assert_repo_link_with_count("issues", 7)
      assert_repo_link_with_count("forks", 3)
      assert_test_selector "fork-detail-updated", text: /Updated/
      assert_test_selector "fork-detail-created", text: /Created/
    end
  end

  test "it renders with no updated time" do
    attributes[:last_updated] = { @repo.id => nil }
    render_inline(Forks::ForkDetailComponent.new(@repo, attributes), allowed_queries: 1)
    assert_test_selector "fork-detail-updated", text: /Never updated/
  end
end
