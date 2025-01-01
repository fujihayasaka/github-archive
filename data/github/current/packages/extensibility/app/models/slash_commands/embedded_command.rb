# typed: strict
# frozen_string_literal: true

module SlashCommands
  class EmbeddedCommand < ApplicationSlashCommand
    extend T::Sig

    category :custom
    allowed_surfaces SlashCommands::ISSUE_COMMENT_SURFACE
    fill :autocomplete_command

    sig { params(context: SlashCommands::Context).returns(T::Boolean) }
    def self.enabled?(context)
      return false unless super
      SlashCommands.embedded_commands_repository?(context.current_repository)
    end

    sig { params(context: SlashCommands::Context).returns(T::Array[SlashCommands::Trigger]) }
    def self.triggers(context)
      source_repository = EmbeddedCommandConfig.source_repository(context.current_repository)
      return [] if source_repository.nil?

      EmbeddedCommandConfig.find_commands(context.current_repository).map do |command|
        SlashCommands::Trigger.new(
          command: SlashCommands::EmbeddedCommand,
          name: command.trigger,
          title: command.title,
          description: command.description,
          command_source_repository: source_repository,
        )
      end
    end

    sig { returns(ActiveSupport::SafeBuffer) }
    def autocomplete_command
      ActiveSupport::SafeBuffer.new <<~MARKDOWN
        /#{context.trigger.name}
      MARKDOWN
    end
  end
end
