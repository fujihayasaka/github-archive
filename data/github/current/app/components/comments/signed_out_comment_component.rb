# typed: true
# frozen_string_literal: true

module Comments
  class SignedOutCommentComponent < ApplicationComponent
    delegate :hydro_click_tracking_attributes, to: :helpers

    def initialize(commentable_type:, repository_id: nil, signup_enabled:)
      @commentable_type = commentable_type
      @repository_id = repository_id
      @signup_enabled = signup_enabled
    end

    private

    attr_reader :commentable_type, :repository_id

    def render?
      !logged_in?
    end

    def signup_enabled?
      @signup_enabled
    end

    def source_label
      if commentable_type == :gist
        "comment-gist"
      else
        "comment-repo"
      end
    end
  end
end
