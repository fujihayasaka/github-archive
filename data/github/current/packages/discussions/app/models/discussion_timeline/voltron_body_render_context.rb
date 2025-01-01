# typed: true
# frozen_string_literal: true

class DiscussionTimeline::VoltronBodyRenderContext
  include DiscussionTimeline::RenderContext

  sig { params(discussion: T.untyped, viewer: T.untyped, cap_filter: T.untyped).void }
  def initialize(discussion, viewer:, cap_filter: nil)
    @discussion = discussion
    @viewer = viewer
    @cap_filter = cap_filter
  end

  # RenderContext module overrides

  attr_reader :cap_filter, :discussion, :viewer

  sig { returns(T.untyped) }
  def render_with_voltron?
    true
  end

  sig { returns(T.untyped) }
  def render_reaction_placeholders?
    true
  end

  sig { returns(T.untyped) }
  def render_discussion?
    true
  end

  sig { override.returns(T.untyped) }
  def will_render_new_marker?
    false
  end
end
