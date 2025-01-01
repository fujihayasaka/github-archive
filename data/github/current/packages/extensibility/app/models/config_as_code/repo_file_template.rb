# typed: true
# frozen_string_literal: true

module ConfigAsCode
  class RepoFileTemplate
    class Template
      extend T::Sig
      extend T::Helpers

      attr_reader :repository, :filename, :tree_entry

      abstract!

      MATCH_FILENAME = /\A(.+)\..+\z/

      def initialize(repository, data, filename, tree_entry)
        @repository = repository
        @data = data
        @filename = filename.force_encoding("UTF-8")
        @tree_entry = tree_entry
      end

      def identifier
        filename.parameterize.to_sym
      end

      def async_repository
        Promise.resolve(repository)
      end

      def valid?
        errors.blank?
      end

      sig { abstract.returns(T::Array[String]) }
      def errors; end
    end

    class YamlTemplate < Template
      attr_reader :validator

      def initialize(repository, data, filename, tree_entry, validator_class)
        super(repository, data, filename, tree_entry)
        @validator = validator_class.new(parsed_data)
      end

      def valid?
        validator.valid?
      end

      def errors
        valid?
        validator.errors.full_messages
      end

      def deprecation_warnings
        valid?
        validator.deprecation_warnings.full_messages
      end

      def parsed_data
        @parsed_data ||= begin
          d = YAML.safe_load(@data)
          d.is_a?(Hash) ? d : {}
        end
      rescue Psych::BadAlias, Psych::DisallowedClass, Psych::SyntaxError
        {}
      end

      # TODO: Following exist for legacy reasons, and should consider being removed.
      # Why? Not every yaml configuration should have these fields.
      def name
        parsed_data["name"]
      end

      # Deprecated
      def about
        parsed_data["about"] || parsed_data["description"]
      end

      def description
        parsed_data["description"]
      end

      def body
        parsed_data["body"]
      end
    end

    class MarkdownTemplate < Template
      # The markdown file itself can't be invalid, although embeds
      # within the markdown will go through validation checks as
      # part of the goomba pipeline and render appropriate errors
      def errors
        []
      end

      def name
        filename.match(MATCH_FILENAME)[1].parameterize.underscore.humanize
      end

      def about
        ""
      end

      def body
        @data
      end
    end

    YAML_FILES = /\A\.(yaml|yml)\z/
    MD_FILES = /\A\.(md)\z/

    COMMAND_CONFIG_REGEX = /\A(\.github\/commands\/.+\.(yaml|yml))\z/
    ISSUE_COMMENT_TEMPLATE_REGEX = /\A(\.github\/ISSUE_COMMENT_TEMPLATE\/.+\.(yaml|yml))\z/

    ISSUE_COMMENT_TEMPLATE = ".github/ISSUE_COMMENT_TEMPLATE"
    COMMAND_CONFIG = ".github/commands"

    DESCRIPTION = {
      ISSUE_COMMENT_TEMPLATE => "issue comment template",
      COMMAND_CONFIG         => "custom slash command",
    }

    DOCS_URL = {
      COMMAND_CONFIG => "#{GitHub.help_url}/early-access/github/save-time-with-slash-commands/syntax-for-user-defined-slash-commands",
    }

    class << self

      # Returns a human readable string describing the kind of config as code template/config.
      #
      # @param repository Repository – the repository to search inside.
      # @param path String – the path of the directory to search inside.
      # @param user User – the user requesting config as code details (typically the current_user).
      #
      # @returns String?
      def description(repository, path, user)
        case
        when ISSUE_COMMENT_TEMPLATE_REGEX.match?(path) && repository&.structured_issue_comment_templates_enabled?
          DESCRIPTION[ISSUE_COMMENT_TEMPLATE]
        when COMMAND_CONFIG_REGEX.match?(path) && slash_commands_config_enabled?(repository, user)
          DESCRIPTION[COMMAND_CONFIG]
        else
          nil
        end
      end

      # Returns a URL to the relevant docs kind of config as code template/config.
      #
      # @param repository Repository – the repository to search inside.
      # @param path String – the path of the directory to search inside.
      # @param user User – the user requesting config as code details (typically the current_user).
      #
      # @returns String?
      def docs_url(repository, path, user)
        if COMMAND_CONFIG_REGEX.match?(path) && slash_commands_config_enabled?(repository, user)
          DOCS_URL[COMMAND_CONFIG]
        end
      end

      # Returns a FileRepoTemplate instance used to query a single type of
      # config as code template/config depending on the given path.
      #
      # @param repository Repository – the repository to search inside.
      # @param path String – the path of the directory to search inside.
      # @param user User – the user requesting config as code details (typically the current_user).
      # @param oid: String? – The object identifier for a commit.
      #
      # @returns FileRepoTemplate?
      def for_path(repository, path, user, oid: nil)
        case
        when ISSUE_COMMENT_TEMPLATE_REGEX.match?(path) && repository&.structured_issue_comment_templates_enabled?
          new_issue_comment_template(repository, oid: oid)
        when COMMAND_CONFIG_REGEX.match?(path) && slash_commands_config_enabled?(repository, user)
          new_command_config(repository, oid: oid)
        else
          nil
        end
      end

      def new_command_config(repository, oid: nil)
        new(repository, COMMAND_CONFIG, validator_class: SlashCommands::Validator, oid: oid)
      end

      def new_webhook_slash_command_config(repository, oid: nil)
        new(repository, SlashCommands::EmbeddedCommandConfig::WEBHOOKS_CONFIG_PATH, validator_class: SlashCommands::EmbeddedCommandValidator, oid: oid)
      end

      def new_snippet_slash_command_config(repository, oid: nil)
        new(repository, SlashCommands::SnippetsConfig::CONFIG_PATH, validator_class: SlashCommands::SnippetsValidator, oid: oid)
      end

      def new_issue_comment_template(repository, oid: nil)
        new(repository, ISSUE_COMMENT_TEMPLATE, validator_class: UI::FormSchema::TemplateValidator, oid: oid)
      end

      def slash_commands_configuration_path?(repository, path, user)
        COMMAND_CONFIG_REGEX.match?(path) && slash_commands_config_enabled?(repository, user)
      end

      private

      def slash_commands_config_enabled?(repo, user)
        user&.custom_slash_commands_enabled? || repo&.slash_commands_enabled?
      end
    end

    attr_reader :oid, :validator_class

    # @param repository Repository – The repository to search inside.
    # @param template_directory String – The path of the directory to search inside.
    # @param template_limit Integer? – The maximum number of templates to return when calling #limited_templates.
    # @param oid: String? – The object identifier for a commit.
    # @param validator_class: Class<UI::Validator>? – The validator class to be used when validating a yaml file.
    #
    def initialize(repository, template_directory, template_limit = nil, oid: nil,  validator_class: nil)
      @repository = repository
      @template_directory = template_directory
      @template_limit = template_limit
      @oid = oid
      @validator_class = validator_class
    end

    def any?
      valid_templates.any?
    end

    def limit_reached?
      return false unless @template_limit

      templates.count >= @template_limit
    end

    def valid_templates
      @valid_templates ||= templates.select(&:valid?)
    end

    def templates
      @templates ||= templates_by_filename.values
    end

    def limited_templates
      return @limited_templates if defined?(@limited_templates)

      @limited_templates = @template_limit ? templates&.slice(0, @template_limit) : templates
    end

    def yaml_templates
      @yaml_templates ||= limited_templates&.select { |t| t.is_a?(YamlTemplate) }
    end

    def md_templates
      @md_templates ||= limited_templates&.select { |t| t.is_a?(MarkdownTemplate) }
    end

    def [](filename)
      templates_by_filename[filename]
    end

    def yaml_templates_by_filename
      @yaml_templates_by_filename ||= template_tree_entries.each_with_object({}) do |tree_entry, result|
        next unless File.extname(tree_entry.name) =~ YAML_FILES
        filename = File.basename(tree_entry.name)
        result[filename] = RepoFileTemplate::YamlTemplate.new(@repository, tree_entry.data, filename, tree_entry, validator_class)
      end
    end

    def md_templates_by_filename
      @md_templates_by_filename ||= template_tree_entries.each_with_object({}) do |tree_entry, result|
        next unless File.extname(tree_entry.name) =~ MD_FILES
        filename = File.basename(tree_entry.name)
        result[filename] = RepoFileTemplate::MarkdownTemplate.new(@repository, tree_entry.data, filename, tree_entry)
      end
    end

    def templates_by_filename
      { **yaml_templates_by_filename, **md_templates_by_filename }
    end

    private


    def template_tree_entries
      if @repository.nil?
        return []
      end

      if @repository.access.broken?
        return []
      end

      begin
        directory = @repository.directory(oid || @repository.default_oid, @template_directory)
        directory&.tree_entries || []
      rescue GitRPC::Error, Repository::CorruptionDetected
        []
      end
    end
  end
end
