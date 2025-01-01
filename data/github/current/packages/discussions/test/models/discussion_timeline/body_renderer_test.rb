# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/conditional_access/filter_test_helper"

class DiscussionTimeline::BodyRendererTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper

  context "#async_body_html_by_record" do
    test "returns a hash of each record to its body html" do
      discussion = create(:discussion, body: "hi")
      comment = create(:discussion_comment, body: "comment")
      nested_comment = create(:discussion_comment, :nested, body: "nested")
      records = [discussion, comment, nested_comment]

      renderer = DiscussionTimeline::BodyRenderer.new(records, context: {
        viewer: discussion.author,
        cap_filter: cap_authorizing_filter([discussion]),
        unfurl_references: true
      })
      expected = {
        discussion => '<p dir="auto">hi</p>',
        comment => '<p dir="auto">comment</p>',
        nested_comment => '<p dir="auto">nested</p>',
      }

      assert_equal expected, renderer.async_body_html_by_record.sync
    end
  end
end
