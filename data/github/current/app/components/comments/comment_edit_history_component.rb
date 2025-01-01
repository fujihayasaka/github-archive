# typed: true
# frozen_string_literal: true

module Comments
  class CommentEditHistoryComponent < ApplicationComponent
    include BotHelper

    attr_reader :comment, :author

    def initialize(comment:, author:)
      @comment = comment
      @author = author
    end

    def render?
      last_user_content_edit.present?
    end

    def edited_by
      editor = last_user_content_edit.editor
      if editor.nil?
        "edited by #{GitHub.ghost_user_login}"
      elsif editor.display_login != @author&.display_login
        # For a bot, we don't want to include the `[bot]` suffix which is included in the login, so we use the slug.
        edit_name = editor.is_a?(Bot) ? editor.slug : editor.display_login

        "edited by #{edit_name}"
      else
        "edited"
      end
    end

    def bot_tag
      bot_identifier(last_user_content_edit.editor).to_s if last_user_content_edit.editor&.display_login != @author&.display_login
    end

    memoize def last_user_content_edit
      comment.async_viewer_can_read_user_content_edits?(current_user).then do |viewer_can_read_user_content_edits|
        next unless viewer_can_read_user_content_edits
        comment.async_latest_user_content_edit.sync
      end.sync
    end
  end
end
