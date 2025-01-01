# typed: true
# frozen_string_literal: true

module SlashCommands
  class StepBuilder::RepositoryDispatch
    def self.build(step_config)
      new(step_config).page
    end

    attr_reader :step_config, :event_type
    def initialize(step_config)
      @step_config = step_config
      @event_type = step_config["eventType"]
    end

    def page
      Page.new(type: :action) do |command|
        render(command)
      end
    end

    def render(command)
      user = command.current_user
      repository =
        if step_config.key?("repository")
          repository_from_step_config = Repository.nwo(step_config["repository"])
          if repository_from_step_config&.readable_by?(command.current_user)
            repository_from_step_config
          else
            command.flash.error = "Repository not found."
            return
          end
        else
          command.current_repository
        end

      if event_type.present? && repository.writable_by?(user)
        repository.dispatch_event(
          user.id,
          event_type,
          command.template_data
        )

        command.flash.notice = "Triggering a `#{event_type}` repository dispatch event"
      elsif event_type.blank?
        command.flash.error = "`eventType` property not set for step `type: repository_dispatch`"
      else
        command.flash.error = "You must have push access to the repository to run this command."
      end
    end
  end
end
