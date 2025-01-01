# typed: true
# frozen_string_literal: true

module SlashCommands
  class SavedRepliesCommand < ApplicationSlashCommand
    category :markdown

    trigger_on name: "replies", title: "Saved replies", description: "Insert one of your saved replies"

    menu :replies_menu
    fill :insert_reply

    DESCRIPTION_MAX_LENGTH = 45

    # arbitrary limit to prevent this from becoming unwieldy as we don't yet have a way to search/filter lists of items
    SAVED_REPLIES_LIMIT = 25

    def replies_menu
      replies = context.current_user.saved_replies.limit(SAVED_REPLIES_LIMIT)

      if replies.any?
        items = replies.map do |reply|
          Item.new(
            id: reply.id,
            text: reply.title,
            description: reply.body.truncate(DESCRIPTION_MAX_LENGTH),
            value: reply.body
          )
        end

        menu(:reply, items: items)
      else
        blankslate "No saved replies", description: ActiveSupport::SafeBuffer.new("You can create one in your <a href=\"/settings/replies\" target=\"_blank\">settings</a>")
      end
    end

    def insert_reply
      data[:reply]
    end
  end
end
