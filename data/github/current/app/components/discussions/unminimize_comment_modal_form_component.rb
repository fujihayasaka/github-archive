# typed: strict
# frozen_string_literal: true

module Discussions
  class UnminimizeCommentModalFormComponent < ApplicationComponent
    extend T::Sig

    sig { params(comment: DiscussionComment, timeline: DiscussionTimeline).void }
    def initialize(comment:, timeline:)
      @comment = comment
      @timeline = timeline
    end

    sig { returns(DiscussionComment) }
    attr_reader :comment

    sig { returns(DiscussionTimeline) }
    attr_reader :timeline
  end
end
