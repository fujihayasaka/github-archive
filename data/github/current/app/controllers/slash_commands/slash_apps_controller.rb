# typed: false
# frozen_string_literal: true
require "liquid"

module SlashCommands
  class SlashAppsController < AbstractRepositoryController

    attr_reader :context, :subject_type, :subject_id

    before_action :login_required
    before_action :ensure_slash_apps_enabled
    before_action :load_context

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Repositories,
      ApplicationRecord::Collab,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Mysql5,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Spokes,
      ApplicationRecord::Configurations,
      ApplicationRecord::IssuesPullRequests,
      ApplicationRecord::Billing,
      only: [:index]

    depends_on_clusters ApplicationRecord::Copilot,
      only: [:index], optional: true

    def index
      respond_to do |format|
        format.html do
          render partial: "slash_commands/suggestions", formats: :html, locals: { grouped_triggers: grouped_triggers, breadcrumbs: [] }
        end
      end
    end

    def update
      command = SlashCommands.find_command(context, command_id: params[:command_id], trigger_name: params[:trigger])
      return render_404 unless command
      command.process

      GlobalInstrumenter.instrument("slash_commands.update", { command: command, platform: "web" })

      render SlashCommands::CommandResponseComponent.new(
        type: command.page.type,
        component: command.component,
        footer: command.footer,
        reload_suggestions: command.page.reloads_suggestions?,
        submit_form: command.page.submit_form,
        custom_event: command.custom_event
      ), layout: false, status: :created
    end

    rescue_from Liquid::SyntaxError do
      render_error "The `#{params[:trigger]}` command contains a syntax error. \
        Please double check the Liquid template syntax used in your command's YAML configuration."
    end

    rescue_from SlashCommands::ApplicationSlashCommand::PageNotFound do
      render_error "There was a problem parsing the `#{params[:trigger]}` slash command. \
        If it is a custom command, please check the syntax used in your command's YAML configuration."
    end

    private

    memoize def grouped_triggers
      triggers = []

      SlashCommands.each_trigger(context) do |trigger, command_class|
        trigger.url = command_path(command_class.id, trigger.name)
        triggers << trigger
      end

      @grouped_triggers = []

      # create a TriggerGroup for each unique category
      triggers.group_by(&:category).each do |group_id, triggers|
        @grouped_triggers << SlashCommands::TriggerGroup.new(id: group_id, triggers: triggers)
      end

      # sort first by ranking, then alphabetically by label
      @grouped_triggers.sort_by do |group|
        [group.sort_importance, group.label]
      end
    end

    def load_context
      @context = SlashCommands::Context.new(
        current_repository: current_repository,
        current_user: current_user,
        subject_gid: params[:subject_gid],
        data: command_data,
        page_number: params[:page],
        surface: params[:surface]
      )
    rescue ArgumentError => error
      head :bad_request
    rescue SlashCommands::Context::InvalidError => error
      head :not_found
    end

    # Combine command data from previous and current step.
    def command_data
      if new_command_data.blank? && previous_command_data.blank?
        {}
      elsif new_command_data.blank?
        previous_command_data
      elsif previous_command_data.blank?
        new_command_data
      else
        previous_command_data.merge(new_command_data)
      end
    end

    def new_command_data
      params.permit![:command] || ActionController::Parameters.new
    end

    memoize def previous_command_data
      if params[:previous_command_data]
        data = JSON.parse(params[:previous_command_data])
        ActionController::Parameters.new(data)
      else
        ActionController::Parameters.new
      end
    rescue JSON::ParserError
      ActionController::Parameters.new
    end

    def command_path(command_id, trigger)
      slash_app_path(
        current_repository.owner,
        current_repository,
        command_id,
        trigger,
        subject_gid: params[:subject_gid],
        surface: params[:surface]
      )
    end

    def render_error(message)
      render SlashCommands::CommandResponseComponent.new(
        type: :error,
        component: SlashCommands::ErrorMessageComponent.new(message: message),
        reload_suggestions: false
      ), layout: false

      set_html_safe
    end

    def slash_apps_enabled?
      current_user.slash_commands_enabled? || current_repository.slash_commands_enabled?
    end

    def ensure_slash_apps_enabled
      return render_404 unless slash_apps_enabled?
    end
  end
end
