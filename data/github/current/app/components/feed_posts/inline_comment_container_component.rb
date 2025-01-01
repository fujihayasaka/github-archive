# typed: true
# frozen_string_literal: true

module FeedPosts
  class InlineCommentContainerComponent < ApplicationComponent
    attr_reader :post_id

    def initialize(post_id:)
      @post_id = post_id
    end
  end
end
