# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionTimeline::VoltronBodyRenderContextTest < GitHub::TestCase
  fixtures do
    @repo_owner = create(:verified_user)
    @public_repo = create(:repository, owner: @repo_owner, has_discussions: true)
    @discussion = create(:discussion, repository: @public_repo)
  end

  context "#render_with_voltron?" do
    test "returns true" do
      render_context = DiscussionTimeline::VoltronBodyRenderContext.new(
        @discussion,
        viewer: @repo_owner,
      )

      assert_equal true, render_context.render_with_voltron?
    end
  end
end
