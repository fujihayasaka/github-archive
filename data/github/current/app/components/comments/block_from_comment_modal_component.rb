# typed: true
# frozen_string_literal: true

module Comments
  class BlockFromCommentModalComponent < ApplicationComponent
    include CommentsHelper

    attr_reader :id, :display_login, :repo, :url

    def initialize(comment:)
      @id = comment.id
      @repo = comment.repository
      @url = comment.url
      @display_login = comment.user.display_login
    end
  end
end
