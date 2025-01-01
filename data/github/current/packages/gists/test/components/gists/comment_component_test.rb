# typed: true
# frozen_string_literal: true

require "test_helper"

class GistsCommentComponentTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers

  fixtures do
    @monalisa = create(:paid_user, name: "monalisa")
  end

  setup do
    @staff = create(:staff_admin_user)
    @user = create(:user)
    @gist = create(:gist, owner: @monalisa)
    @gist_comment = create(:gist_comment, gist: @gist, user: @monalisa, body: "a good comment")
  end

  test "renders header" do
    as @gist_comment.user
    render_inline Gists::CommentComponent.new(gist: @gist, comment: @gist_comment), allowed_queries: 1

    assert_test_selector "#{@gist_comment.id}-comment-header"
  end

  test "renders body" do
    as @gist_comment.user
    render_inline Gists::CommentComponent.new(gist: @gist, comment: @gist_comment), allowed_queries: 1

    assert_selector ".comment-body", text: "a good comment"
  end

  test "renders minimized" do
    as @gist_comment.user
    @gist_comment.set_minimized(@gist_comment.user, "reason", "spam", @gist_comment.user, false)

    render_inline Gists::CommentComponent.new(gist: @gist, comment: @gist_comment, render_minimized: false), allowed_queries: 1

    assert_selector ".minimized-comment summary .Details-content--closed", text: "Show comment"
    assert_selector ".minimized-comment summary .Details-content--open", text: "Hide comment"
    assert_selector ".timeline-comment-header-text", text: "This comment was marked as spam."
    refute_selector ".comment-body"
  end

  test "renders show/hide links, staff minimized message for comment author" do
    @gist_comment.set_minimized(@staff, "reason", "abuse", @gist_comment.user, true)

    as @gist_comment.user
    render_inline Gists::CommentComponent.new(gist: @gist, comment: @gist_comment, render_minimized: false), allowed_queries: 1

    assert_selector ".minimized-comment summary .Details-content--closed", text: "Show comment"
    assert_selector ".minimized-comment summary .Details-content--open", text: "Hide comment"
    assert_selector ".timeline-comment-header-text", text: "This comment was marked as a violation of GitHub Acceptable Use Policies"
    assert_selector "a[href='https://docs.github.com/site-policy/acceptable-use-policies/github-acceptable-use-policies']", text: "GitHub Acceptable Use Policies"
  end

  test "renders show/hide more links, staff minimized message if user is staff" do
    @gist_comment.set_minimized(@staff, "reason", "abuse", @gist_comment.user, true)

    as @staff
    render_inline Gists::CommentComponent.new(gist: @gist, comment: @gist_comment, render_minimized: false), allowed_queries: 1

    assert_selector ".minimized-comment summary .Details-content--closed", text: "Show comment"
    assert_selector ".minimized-comment summary .Details-content--open", text: "Hide comment"
    assert_selector ".timeline-comment-header-text", text: "This comment was marked as a violation of GitHub Acceptable Use Policies"
    assert_selector "a[href='https://docs.github.com/site-policy/acceptable-use-policies/github-acceptable-use-policies']", text: "GitHub Acceptable Use Policies"
  end

  test "does not render show/hide more link, and renders staff minimized message if user is not comment author, or staff" do
    @gist_comment.set_minimized(@staff, "reason", "abuse", @gist_comment.user, true)

    refute_equal @gist_comment.user, @user
    refute @user.employee?

    as @user
    render_inline Gists::CommentComponent.new(gist: @gist, comment: @gist_comment, render_minimized: false), allowed_queries: 1

    refute_selector ".minimized-comment summary .Details-content--closed", text: "Show comment"
    refute_selector ".minimized-comment summary .Details-content--open", text: "Hide comment"
    assert_selector ".timeline-comment-header-text", text: "This comment was marked as a violation of GitHub Acceptable Use Policies"
    assert_selector "a[href='https://docs.github.com/site-policy/acceptable-use-policies/github-acceptable-use-policies']", text: "GitHub Acceptable Use Policies"
  end

  test "does not render show/hide more link, and renders staff minimized message if logged out" do
    @gist_comment.set_minimized(@staff, "reason", "abuse", @gist_comment.user, true)

    render_inline Gists::CommentComponent.new(gist: @gist, comment: @gist_comment, render_minimized: false), allowed_queries: 1

    refute_selector ".minimized-comment summary .Details-content--closed", text: "Show comment"
    refute_selector ".minimized-comment summary .Details-content--open", text: "Hide comment"
    assert_selector ".timeline-comment-header-text", text: "This comment was marked as a violation of GitHub Acceptable Use Policies"
    assert_selector "a[href='https://docs.github.com/site-policy/acceptable-use-policies/github-acceptable-use-policies']", text: "GitHub Acceptable Use Policies"
  end
end
