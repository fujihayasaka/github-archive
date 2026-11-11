# typed: true
# frozen_string_literal: true

module SlashCommands
  class UserDefinedConfig
    InvalidStepError = Class.new(StandardError)

    MAX_STEPS = 25
    CONFIG_PATH = ".github/commands"
    STEP_BUILDERS = {
      "menu" => StepBuilder::Menu,
      "fill" => StepBuilder::Fill,
      "form" => StepBuilder::Form,
      "repository_dispatch" => StepBuilder::RepositoryDispatch,
    }

    SHORTCUT_STEP_BUILDERS = {
      "flash" => StepBuilder::Flash,
      "graphql" => StepBuilder::Graphql,
      "addComment" => StepBuilder::AddComment,
      "addLabels" => StepBuilder::AddLabels,
      "addAssignees" => StepBuilder::AddAssignees,
      "addToProject" => StepBuilder::AddToProject,
      "createIssue" => StepBuilder::CreateIssue,
    }

    def self.from_context(context)
      source_repositories(context).flat_map do |repository|
        ConfigAsCode::RepoFileTemplate.new_command_config(repository).yaml_templates.map do |schema_template|
          new(
            schema_template.parsed_data,
            context: context,
            command_source_repository: repository,
          )
        end
      end
    end

    # Given a context, returns the list of repositories that may contain user-defined commands.
    def self.source_repositories(context)
      repositories = [context.current_repository]

      if context.current_repository.in_organization? && FeatureFlag.vexi.enabled?(:organization_commands, context.current_user, default: false)
        repositories << context.current_repository.organization.private_config_as_code_repo
      end

      if FeatureFlag.vexi.enabled?(:personal_commands, context.current_user, default: false)
        repositories << context.current_user.private_config_as_code_repo
      end

      # NOTE: We only read slash command YAML from private repositories. This
      #       ensures users in the private beta don't accidentally leak the feature.
      #       Once this we can re-evaluate this choice.
      repositories.compact.uniq.select(&:writable?).select(&:private?)
    end

    attr_reader :data, :context, :command_source_repository

    def initialize(data, context:, command_source_repository:)
      @data = data
      @context = context
      @command_source_repository = command_source_repository
    end

    def enabled?
      return false if step_count > MAX_STEPS
      surfaces.include?(context.surface.to_s)
    end

    def step_count
      data["steps"]&.count || 0
    end

    def surfaces
      @surfaces ||= begin
        surfaces = data["surfaces"].present? ? Array(data["surfaces"]) : SlashCommands::SUPPORTED_SURFACES
        SlashCommands.expand_surfaces(surfaces.map(&:to_sym)).map(&:to_s)
      end
    end

    def trigger
      SlashCommands::Trigger.new(
        command: SlashCommands::UserDefinedCommand,
        name: data["trigger"],
        title: data["title"],
        description: data["description"],
        command_source_repository: command_source_repository,
      )
    end

    def pages
      (data["steps"] || []).map do |step_config|
        step_builder_for(step_config)
      end
    rescue InvalidStepError => e
      [
        Page.new(type: :action) do |command|
          command.flash.error = e.message
        end
      ]
    end

    private

    def step_builders
      if FeatureFlag.vexi.enabled?(:shortcuts, context.current_user, default: false)
        STEP_BUILDERS.merge(SHORTCUT_STEP_BUILDERS)
      else
        STEP_BUILDERS
      end
    end

    def step_builder_for(step_config)
      step_type = step_config["type"]
      step_builder = step_builders[step_type]

      if step_builder
        step_builder.build(step_config)
      else
        raise InvalidStepError, "Command contains invalid step type: #{step_type}"
      end
    end
  end
end
