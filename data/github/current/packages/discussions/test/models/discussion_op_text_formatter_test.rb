# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionOpTextFormatterTest < GitHub::TestCase
  context "#format" do
    test "add blockquote tag to body" do
      discussion_body = "body"
      discussion = create(:discussion, body: discussion_body)
      expected = "\n### Discussed in #{discussion.url}\n\n"
      expected += "<div type='discussions-op-text'>\n\n"
      expected += "<sup>Originally posted by **#{discussion.user.login}** #{discussion.created_at.strftime("%B %e, %Y")}</sup>\n"
      expected += "body</div>"

      assert_equal DiscussionOpTextFormatter.new(discussion).format, expected
    end

    test "can handle if body is nil" do
      issue = create(:issue)
      # use the "converting" state to allow for a nil body.
      discussion = create(:discussion, body: nil, state: :converting, issue: issue)

      expected = "\n### Discussed in #{discussion.url}\n\n"
      expected += "<div type='discussions-op-text'>\n\n"
      expected += "<sup>Originally posted by **#{discussion.user.login}** #{discussion.created_at.strftime("%B %e, %Y")}</sup>\n"
      expected += "</div>"

      assert_equal DiscussionOpTextFormatter.new(discussion).format, expected
    end

    test "works when discussion user has been deleted" do
      discussion_body = "body"
      discussion = create(:discussion, body: discussion_body)
      discussion.user.delete
      discussion.reload

      expected = "\n### Discussed in #{discussion.url}\n\n"
      expected += "<div type='discussions-op-text'>\n\n"
      expected += "<sup>Originally posted by **ghost** #{discussion.created_at.strftime("%B %e, %Y")}</sup>\n"
      expected += "body</div>"

      assert_equal DiscussionOpTextFormatter.new(discussion).format, expected
    end
  end
end
