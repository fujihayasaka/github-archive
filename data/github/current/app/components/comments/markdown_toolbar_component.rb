# typed: true
# frozen_string_literal: true
module Comments
  class MarkdownToolbarComponent < ApplicationComponent
    include CachedOcticonHelper
    include CommentBoxAnalyticsHelper

    attr_reader :textarea_id

    def initialize(
      textarea_id:,
      **system_arguments
    )

      @system_arguments = system_arguments
      @system_arguments[:tag] = :"markdown-toolbar"
      @system_arguments[:classes] = class_names(
        @system_arguments[:classes],
        "CommentBox-toolbar"
      )
      @system_arguments[:role] = "presentation"
      @system_arguments[:for] = textarea_id
      @system_arguments[:data] = @system_arguments[:data].to_h.merge({ "no-focus": true })

      @textarea_id = textarea_id
      @prepend_items = []
      @append_items = []
    end

    def before_render
      content
    end

    def hotkey(hotkey)
      request&.user_agent&.match?(/Macintosh/) ? "Meta+#{hotkey}" : "Control+#{hotkey}"
    end

    def prepend_item(**system_arguments)
      @prepend_items << system_arguments
    end

    def append_item(**system_arguments)
      @append_items << system_arguments
    end
  end
end
