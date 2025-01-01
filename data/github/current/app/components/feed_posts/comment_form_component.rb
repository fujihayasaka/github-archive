# typed: true
# frozen_string_literal: true

module FeedPosts
  class CommentFormComponent < ApplicationComponent
    include UploadHelper

    delegate :mention_suggestion_params, to: :helpers

    attr_reader :textarea_id

    def initialize(textarea_id:)
      @textarea_id = textarea_id
    end

    def use_fixed_width_font?
      current_user&.use_fixed_width_font?
    end
  end
end
