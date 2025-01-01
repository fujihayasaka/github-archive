# typed: true
# frozen_string_literal: true

module SlashCommands
  class DetailsCommand < ApplicationSlashCommand
    category :markdown

    trigger_on name: "details", title: "Details", description: "Add a details tag to hide content behind a visible heading"

    fill :markdown

    def markdown
      ActiveSupport::SafeBuffer.new <<~MARKDOWN
        <details><summary>Details</summary>
        <p>

        %cursor%

        </p>
        </details>
      MARKDOWN
    end
  end
end
