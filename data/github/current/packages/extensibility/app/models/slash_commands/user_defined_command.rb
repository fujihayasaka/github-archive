# typed: true
# frozen_string_literal: true

module SlashCommands
  class UserDefinedCommand < ApplicationSlashCommand
    category :custom

    COMMAND_NOT_FOUND_PAGE = Page.new(type: :action) do |command|
      command.flash.error = "Command not found"
    end

    def self.triggers(context)
      user_defined_configs = UserDefinedConfig.from_context(context)

      user_defined_configs.select(&:enabled?).map(&:trigger)
    end

    def self.enabled?(context)
      super && (context.current_user.feature_enabled?(:user_defined_commands) || context.current_repository.feature_enabled?(:user_defined_commands))
    end

    def template_data
      {
        data: data.respond_to?(:permit!) ? data.permit!.to_h : data,
        command: {
          surface: context.surface.to_s,
          resource: {
            type: context.subject&.class&.sti_name,
            id: context.subject&.global_relay_id,
            number: context.subject&.number
          },
          repository: {
            full_name: current_repository.nwo,
            node_id: current_repository.global_relay_id,
            clone_url: current_repository.clone_url
          },
          user: {
            id: current_user.global_relay_id,
            login: current_user.login,
          }
        }
      }.deep_stringify_keys
    end

    def pages
      return @pages if defined?(@pages)

      @pages =
        if user_defined_config
          user_defined_config.pages
        else
          [COMMAND_NOT_FOUND_PAGE]
        end
    end

    def process
      loop do
        if last_page? || page.ui?
          # When we're on the last page or a UI page, don't continue.
          return super
        else
          result = super

          if flash.error.present?
            # When there is an error present, don't continue.
            return result
          else
            next_page_and_reset
          end
        end
      end
    end

    private

    def next_page_and_reset
      context.next_page!
      @page = nil
      @flash = Flash.new
    end

    def user_defined_config
      return @user_defined_config if defined?(@user_defined_config)

      config = user_defined_configs.find do |config|
        config.trigger.name == context.trigger.name
      end

      @user_defined_config = config&.enabled? ? config : nil
    end

    def user_defined_configs
      @user_defined_configs ||= UserDefinedConfig.from_context(context)
    end
  end
end
