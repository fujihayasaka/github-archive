# typed: strict
# frozen_string_literal: true

module SlashCommands
  class SnippetsCommand < ApplicationSlashCommand
    extend T::Sig

    category :markdown
    fill :fill_markdown

    sig { params(context: SlashCommands::Context).returns(T::Boolean) }
    def self.enabled?(context)
      return false unless super
      SlashCommands.snippets_repository?(context.current_repository)
    end

    sig { params(context: SlashCommands::Context).returns(T::Array[SlashCommands::Trigger]) }
    def self.triggers(context)
      source_repository = SnippetsConfig.source_repository(context.current_repository)
      return [] if source_repository.nil?

      triggers = []
      SnippetsConfig.find_commands(context.current_repository).each do |command|
        next unless command.supported_surface?(context.surface.to_s)

        triggers << SlashCommands::Trigger.new(
          command: SlashCommands::SnippetsCommand,
          name: command.trigger,
          title: command.title,
          description: command.description,
          command_source_repository: source_repository,
        )
      end

      triggers
    end

    sig { returns(T.nilable(String)) }
    def fill_markdown
      command = SnippetsConfig.find_commands(context.current_repository).find { |command| command.trigger == context.trigger.name }
      command&.get_value
    end
  end
end
