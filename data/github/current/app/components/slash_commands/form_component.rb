# typed: true
# frozen_string_literal: true

module SlashCommands
  class FormComponent < ApplicationComponent
    delegate :breadcrumbs, :data, :next_page_number, to: :command
    attr_reader :command, :form_component, :pt

    def initialize(command:, fields: [], actions: nil, pt: 0)
      @command = command
      @pt = pt

      @form_component = UI::FormComponent.new(
        method: :patch,
        fields: fields,
        actions: actions,
        allow_method_names_outside_object: true,
        classes: "js-slash-command-suggestion-form"
      ).with_model(
        name: "command",
        attributes: command.data,
        errors: command.errors
      )
    end

    def with_actions(*components)
      form_component.with_actions(*components)

      self
    end

    def with_fields(*components)
      form_component.with_fields(*components)

      self
    end

    def path
      slash_app_path(
        command.current_repository.owner,
        command.current_repository,
        command.id,
        command.trigger.name,
        subject_gid: command.context.subject_gid,
        surface: command.context.surface
      )
    end
  end
end
