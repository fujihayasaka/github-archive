# typed: true
# frozen_string_literal: true

module CommandPalette
  module Commands
    class CommandFinder
      COMMANDS = [
        PinIssue,
        UnpinIssue,
        CloseIssue,
        CloneCopyCli,
        CloneCopyHttps,
        CloneCopySsh,
        ReopenIssue,
        ReadyForReview
      ]
      def self.instances(context)
        COMMANDS.map { |klass| klass.new(context) }
      end

      def self.find_commands(context)
        commands = self.instances(context).filter(&:scope_matches?)

        GitHub.dogstats.distribution_time("command_palette.enabled.find_commands_duration", tags: ["scope_type:#{context.scope.type.name}"]) do
          commands.filter(&:instrumented_enabled?)
        end
      end

      def self.find_command(context, displayed_as)
        self.instances(context).find do |command|
          next unless command.scope_matches?
          next unless command.instrumented_enabled?

          command.display.name == displayed_as
        end
      end
    end
  end
end
