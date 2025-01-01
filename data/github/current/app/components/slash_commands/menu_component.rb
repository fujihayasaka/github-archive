# typed: true
# frozen_string_literal: true

module SlashCommands
  class MenuComponent < ApplicationComponent

    attr_reader :items, :command, :next_page, :breadcrumbs, :input_name

    def initialize(command:, items:, next_page:, breadcrumbs:, name:)
      @items = Item.wrap(items)
      @command = command
      @next_page = next_page
      @breadcrumbs = breadcrumbs
      @input_name = "command[#{name || "value"}]"
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

    def hidden_fields(item_value)
      {
        "page" => next_page,
        "previous_command_data" => command.data.to_json,
        input_name => item_value
      }
    end
  end
end
