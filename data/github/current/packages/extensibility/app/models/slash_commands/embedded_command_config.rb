# typed: strict
# frozen_string_literal: true

module SlashCommands
  class EmbeddedCommandConfig
    extend T::Sig

    WEBHOOKS_CONFIG_PATH = ".github/slash_commands/webhooks"

    sig { params(repository: Repository).returns(T::Array[EmbeddedCommandConfig]) }
    def self.find_commands(repository)
      source = source_repository(repository)
      return [] if source.nil?

      commands = []
      ConfigAsCode::RepoFileTemplate.new_webhook_slash_command_config(source).yaml_templates.each do |template|
        next unless template.valid?
        data = template.parsed_data

        commands.push(new(
          repository: repository,
          trigger: data["trigger"],
          title: data["title"],
          description: data["description"]
        ))
      end

      commands
    end

    sig { params(repository: Repository).returns(T.nilable(Repository)) }
    def self.source_repository(repository)
      return unless repository.in_organization?

      T.must(repository.owner).private_config_as_code_repo
    end

    sig { returns(Repository) }
    attr_reader :repository

    sig { returns(String) }
    attr_reader :trigger

    sig { returns(String) }
    attr_reader :title

    sig { returns(String) }
    attr_reader :description

    sig { params(repository: Repository, trigger: String, title: String, description: String).void }
    def initialize(repository:, trigger:, title:, description:)
      @repository = repository
      @trigger = trigger
      @title = title
      @description = description
    end
  end
end
