# typed: true
# frozen_string_literal: true

require "test_helper"

class GistsCommentBodyComponentTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers

  fixtures do
    @monalisa = create(:paid_user, name: "monalisa")
  end

  setup do
    @gist = create(:gist, owner: @monalisa)
    @gist_comment = create(:gist_comment, gist: @gist, user: @monalisa)
  end

  test "doesn't render if no body html" do
    render_inline Gists::CommentBodyComponent.new(comment: @gist_comment, body_html: nil)

    refute_component_rendered
  end

  test "renders body html" do
    test_body = GitHub::HTMLSafeString.make("<div class='test'>testing</div>")
    render_inline Gists::CommentBodyComponent.new(comment: @gist_comment, body_html: test_body)

    assert_selector "div.test", text: "testing"
  end

  test "renders body html with a 'soft-wrap' class" do
    test_body = GitHub::HTMLSafeString.make("soft-wrap-test")
    render_inline Gists::CommentBodyComponent.new(comment: @gist_comment, body_html: test_body)

    assert_selector "div.comment-body.soft-wrap", text: "soft-wrap-test"
  end

  test "does not render body html with an 'email-format' class" do
    test_body = GitHub::HTMLSafeString.make("not-email-test")
    render_inline Gists::CommentBodyComponent.new(comment: @gist_comment, body_html: test_body)

    refute_selector "div.comment-body.email-format"
  end

  context "with email format" do
    test "renders body html with an 'email-format' class" do
      email_comment = create(:gist_comment, gist: @gist, user: @monalisa, formatter: "email")
      test_body = GitHub::HTMLSafeString.make("email-format-test")
      render_inline Gists::CommentBodyComponent.new(comment: email_comment, body_html: test_body)

      assert_selector "div.comment-body.email-format", text: "email-format-test"
    end
  end
end
