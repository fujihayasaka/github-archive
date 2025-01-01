# typed: strict
# frozen_string_literal: true

class ProcessEmbeddedSlashCommandsJob < ApplicationJob
  extend T::Sig

  queue_as :process_embedded_slash_commands_job
  retry_on_dirty_exit

  sig { params(subject: IssueComment).void }
  def perform(subject:)
    return unless SlashCommands.embedded_commands_candidate?(subject)

    commands = extract_commands(subject.body)
    return if commands.empty?

    configured_commands = SlashCommands::EmbeddedCommandConfig.find_commands(T.must(subject.repository))

    commands.each do |command|
      configured_commands.each do |configured_command|
        if configured_command.trigger == command
          GitHub.dogstats.increment("embedded_slash_commands.extracted")
          GitHub.instrument("slash_command.posted", command: command, subject_type: subject.class.name, subject_id: subject.id)
        end
      end
    end
  end

  sig { params(body: String).returns(T::Array[String]) }
  def extract_commands(body)
    return [] unless body.present?
    SlashCommands.extract_embedded_commands(body)
  end
end
