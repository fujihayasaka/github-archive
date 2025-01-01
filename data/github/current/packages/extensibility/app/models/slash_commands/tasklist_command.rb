# typed: true
# frozen_string_literal: true

module SlashCommands
  class TasklistCommand < ApplicationSlashCommand
    category :markdown

    trigger_on name: "tasklist", title: "Tasklist", description: "Add a Tasklist block"

    allowed_surfaces SlashCommands::ISSUE_BODY_SURFACE, SlashCommands::PULL_REQUEST_BODY_SURFACE

    fill :markdown

    def self.enabled?(context)
      super && context.current_repository.owner.feature_enabled?(:tasklist_block)
    end

    def markdown
      ActiveSupport::SafeBuffer.new <<~MARKDOWN
        ```[tasklist]
        ### Tasks
        - [ ] %cursor%
        ```
      MARKDOWN
    end
  end
end
