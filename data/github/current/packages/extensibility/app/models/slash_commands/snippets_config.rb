# typed: strict
# frozen_string_literal: true

module SlashCommands
  class SnippetsConfig
    extend T::Sig

    CONFIG_PATH = "slash_commands/snippets"

    sig { params(repository: Repository).returns(T::Array[SnippetsConfig]) }
    def self.find_commands(repository)
      source = source_repository(repository)
      return [] if source.nil?

      commands = []
      ConfigAsCode::RepoFileTemplate.new_snippet_slash_command_config(source).yaml_templates.each do |template|
        next unless template.valid?
        data = template.parsed_data

        commands.push(new(
          repository: source,
          trigger: data["trigger"],
          surfaces: data["surfaces"] || [],
          title: data["title"],
          description: data["description"],
          value: data["value"],
          value_source: data["value_source"],
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

    sig { returns(T::Array[String]) }
    attr_reader :surfaces

    sig { returns(String) }
    attr_reader :title

    sig { returns(String) }
    attr_reader :description

    sig { returns(T.nilable(String)) }
    attr_reader :value

    sig { returns(T.nilable(String)) }
    attr_reader :value_source

    sig { params(repository: Repository, trigger: String, title: String, description: String, value: T.nilable(String), value_source: T.nilable(String), surfaces: T.any(String, T::Array[String])).void }
    def initialize(repository:, trigger:, title:, description:, value: nil, value_source: nil, surfaces: [])
      @repository = repository
      @trigger = trigger
      @title = title
      @description = description
      @value = value
      @value_source = value_source

      if surfaces.is_a?(Array)
        @surfaces = T.let(SlashCommands.expand_surfaces(surfaces.map(&:to_sym)).map(&:to_s), T::Array[String])
      elsif surfaces.is_a?(String) && surfaces == SlashCommands::ALL_SURFACE
        @surfaces = T.let(SlashCommands::SUPPORTED_SURFACES.map(&:to_s), T::Array[String])
      end

      if @value.nil? && @value_source.nil?
        raise ArgumentError.new("Either value or value_source must be provided")
      end
    end

    sig { params(surface: String).returns(T::Boolean) }
    def supported_surface?(surface)
      surfaces.empty? || surfaces.include?(surface)
    end

    sig { returns(T.nilable(String)) }
    def get_value
      return value if value.present?

      if value_source.present?
        begin
          value = repository.tree_entry(repository.default_oid, value_source)&.data
        rescue GitRPC::NoSuchPath
          value = ""
        end
      end

      value
    end
  end
end
