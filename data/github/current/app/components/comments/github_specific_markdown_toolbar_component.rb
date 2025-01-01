# typed: true
# frozen_string_literal: true
module Comments
  class GitHubSpecificMarkdownToolbarComponent < ApplicationComponent
    include CommentBoxAnalyticsHelper
    include ReactHelper

    attr_reader :textarea_id, :file_chooser_id, :saved_reply_context, :hide_saved_replies, :suggestion_button_path, :pull_request, :repository, :subject_name, :hide_mentions, :hide_cross_references, :allow_attachments, :copilot_summary_enabled, :copilot_text_completion_enabled

    def initialize(
      textarea_id:,
      saved_reply_context: nil,
      hide_saved_replies: false,
      allows_suggested_changes: false,
      suggestion_button_path: nil,
      pull_request: nil,
      repository: nil,
      slash_commands_enabled: false,
      hide_mentions: false,
      hide_cross_references: false,
      allow_attachments: true,
      tasklist_blocks_enabled: false,
      copilot_summary_enabled: false,
      copilot_text_completion_enabled: false
    )
      @file_chooser_id = "fc-#{textarea_id}"
      @textarea_id = textarea_id
      @saved_reply_context = saved_reply_context
      @hide_saved_replies = hide_saved_replies
      @allows_suggested_changes = allows_suggested_changes
      @suggestion_button_path = suggestion_button_path
      @pull_request = pull_request
      @repository = repository
      @slash_commands_enabled = slash_commands_enabled
      @hide_mentions = hide_mentions
      @hide_cross_references = hide_cross_references
      @allow_attachments = allow_attachments
      @tasklist_blocks_enabled = tasklist_blocks_enabled
      @copilot_summary_enabled = copilot_summary_enabled
      @copilot_text_completion_enabled = copilot_text_completion_enabled
    end

    def show_suggested_changes_button?
      @allows_suggested_changes
    end

    def show_slash_commands_button?
      @slash_commands_enabled
    end

    def show_tasklist_blocks_button?
      @tasklist_blocks_enabled
    end

    def show_copilot_button?
      ghost_pilot_enabled? || pr_summary_enabled?
    end

    def pr_summary_enabled?
      @copilot_summary_enabled
    end

    def ghost_pilot_enabled?
      @copilot_text_completion_enabled
    end

    def show_file_chooser_button?
      allow_attachments && attachments_enabled?
    end

    def any_buttons_to_append?
      !hide_mentions || !hide_cross_references || !hide_saved_replies ||
        show_slash_commands_button? || show_file_chooser_button?
    end
  end
end
