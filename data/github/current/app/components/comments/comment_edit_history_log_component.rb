# typed: true
# frozen_string_literal: true

module Comments
  class CommentEditHistoryLogComponent < ApplicationComponent
    include AvatarHelper
    include BotHelper

    EDITS_LIMIT = 100

    attr_reader :comment

    def initialize(comment:)
      @comment = comment
    end

    def render?
      edits.present?
    end

    memoize def edits
      if viewer_can_read_user_content_edits?
        edits_query.limit(EDITS_LIMIT)
      else
        edits_query.none
      end
    end

    def edit_count
      includes_created_edit ? edits_total_count - 1 : edits_total_count
    end

    memoize def edits_total_count
      edits_query.count
    end

    memoize def includes_created_edit
      # `edits` originally ordered by ID DESC
      # which means that the first edit (creation) will be the last in the `edits` array
      # UserContentEditable#include_created_edits? is true when the first edit's creation date equals to the 2nd edit's creation date
      # Hence we do `edits#reverse`; this way we won't change the implementation of UserContentEditable#include_created_edits?
      # which might break behaviour at other call sites
      # For a special case when number of edits exceeding EDITS_LIMIT, we don't want to include the preloaded content_edits
      # Instead we would like to execute the extra comment#user_content_edits at UserContentEditable#include_created_edits?
      # to ensure that the first edit (of creation) is included at the list of edits ,and hence we have an accurate result
      preloaded_edits = edits_total_count <= EDITS_LIMIT ? edits.reverse : nil
      comment.includes_created_edit?(content_edits: preloaded_edits)
    end

    private

    def edits_query
      if comment.is_a?(PullRequest)
        comment.issue.user_content_edits.includes(:editor, :deleted_by).order(id: :desc)
      else
        comment.user_content_edits.includes(:editor, :deleted_by).order(id: :desc)
      end
    end

    def viewer_can_read_user_content_edits?
      comment.viewer_can_read_user_content_edits?(current_user)
    end

    # Returns the display name for an editor (user or bot).
    # For AgenticApp bots, returns the display_name (e.g., "Claude").
    # For regular bots, returns the slug (without [bot] suffix).
    # For regular users, returns the display_login.
    def editor_display_name(editor)
      return nil if editor.nil?

      if editor.is_a?(Bot)
        # Use memoized lookup to avoid repeated agentic app lookups for the same bot
        agentic_app = agentic_app_for_bot(editor)
        agentic_app ? agentic_app.display_name : editor.slug
      else
        editor.display_login
      end
    end

    # Memoized lookup of AgenticApp for a bot.
    # Caches results per bot_id to avoid redundant lookups when the same bot
    # appears multiple times in the edits list (as editor or deleted_by).
    def agentic_app_for_bot(bot)
      @agentic_apps_cache ||= {}
      return @agentic_apps_cache[bot.id] if @agentic_apps_cache.key?(bot.id)

      @agentic_apps_cache[bot.id] = bot.async_agentic_app.sync
    end

    # Override bot_identifier to use cached AgenticApp lookup.
    # This avoids redundant Apps::Privileged.capable? calls since we already
    # know if the bot is an AI agent from the AgenticApp lookup used for display names.
    def bot_identifier(actor)
      return super unless actor.is_a?(Bot)

      # If we have a cached AgenticApp for this bot, it's an AI agent
      agentic_app = agentic_app_for_bot(actor)
      agentic_app ? ai_identifier_tag : bot_identifier_tag
    end

    # Override avatar_class_names to use cached AgenticApp lookup for bots.
    # This avoids redundant AgenticApp.agent_for_integration_id calls which
    # would load integrations for each agent in the registry.
    def avatar_class_names(actor)
      if actor.is_a?(Bot)
        # Use cached AgenticApp lookup - if it's an agentic app, use avatar-user class
        agentic_app_for_bot(actor).present? ? "avatar avatar-user" : "avatar"
      else
        super
      end
    end
  end
end
