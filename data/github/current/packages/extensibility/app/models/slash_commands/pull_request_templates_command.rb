# typed: strict
# frozen_string_literal: true

module SlashCommands
  class PullRequestTemplatesCommand < ApplicationSlashCommand
    extend T::Sig

    category :markdown

    trigger_on name: "templates", title: "Templates", description: "Insert your pull request template"
    allowed_surfaces SlashCommands::PULL_REQUEST_BODY_SURFACE

    feature_flag :slash_commands_templates_command

    fill :insert_template

    sig { params(context: SlashCommands::Context).returns(T::Boolean) }
    def self.enabled?(context)
      super && context.current_repository.preferred_pull_request_template.present?
    end

    sig { returns(String) }
    def insert_template
      context.current_repository.preferred_pull_request_template.data
    end
  end
end
