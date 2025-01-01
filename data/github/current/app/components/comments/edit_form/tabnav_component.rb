# typed: true
# frozen_string_literal: true

module Comments
  module EditForm
    class TabnavComponent < ApplicationComponent
      attr_reader :comment, :saved_reply_context, :textarea_id, :slash_commands_enabled, :tasklist_blocks_enabled, :copilot_summary_enabled, :copilot_text_completion_enabled, :current_repository

      def initialize(comment:, saved_reply_context:, textarea_id:, slash_commands_enabled: false, tasklist_blocks_enabled: false, copilot_summary_enabled: false, copilot_text_completion_enabled: false, current_repository: nil)
        @comment = comment
        @saved_reply_context = saved_reply_context
        @textarea_id = textarea_id
        @slash_commands_enabled = slash_commands_enabled
        @tasklist_blocks_enabled = tasklist_blocks_enabled
        @copilot_summary_enabled = copilot_summary_enabled
        @copilot_text_completion_enabled = copilot_text_completion_enabled
        @current_repository = current_repository
      end
    end
  end
end
