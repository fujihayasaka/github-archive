# typed: false
# frozen_string_literal: true

module SlashCommands::EmbeddedCommands
  extend ActiveSupport::Concern

  def should_process_slash_commands?
    SlashCommands.embedded_commands_candidate?(self) && contains_slash_commands?
  end

  def contains_slash_commands?
    body.present? && SlashCommands.may_contain_commands?(body)
  end

  def process_slash_commands
    ProcessEmbeddedSlashCommandsJob.perform_later(subject: self)
  end
end
