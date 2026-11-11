# typed: true
# frozen_string_literal: true

module CommandPalette
  module Commands
    class ApplicationCommand
      DEFAULT_PRIORITY = 10
      DEFAULT_HINT = "Run Command"
      DEFAULT_ICON = "plus-circle"
      class << self
        attr_accessor :display, :scope_types
      end

      def self.inherited(subclass)
        subclass.scope_types = []
      end

      def self.display_as(title, name: nil, icon: DEFAULT_ICON, hint: DEFAULT_HINT, priority: DEFAULT_PRIORITY)
        self.display = Display.new(
          title: title,
          name: name || title,
          icon: Icons::Octicon.new(name: icon),
          hint: hint,
          priority: priority,
        )
      end

      def self.scope_type(*types)
        self.scope_types.push(*types)
      end

      attr_reader :context
      delegate :scope, :current_user, to: :context
      delegate :display, :scope_types, to: :class

      def initialize(context)
        @context = context
      end

      def enabled?
        false
      end

      def execute
        raise NotImplementedError
      end

      def authorize_content(kind, action, data = {})
        authorization = ContentAuthorizer.authorize(current_user, kind, action, data)
        authorization.passed?
      end

      def instrumented_enabled?
        GitHub.dogstats.distribution_time("command_palette.enabled.command_duration", tags: ["command:#{self.class.name}"]) do
          enabled?
        end
      end

      def run
        GitHub.dogstats.distribution_time("command_palette.run.command_duration", tags: ["command:#{self.class.name}"]) do
          execute
        end
      end

      def scoped_object
        scope.object
      end

      def scope_matches?
        scope_types.length == 0 || scope_types.include?(scoped_object.class.name)
      end

      def display_flash(type:, message:)
        Response.new(action: Response::ACTION_DISPLAY_FLASH, arguments: {
          type: type,
          message: message,
        })
      end

      def to_result
        Results::CommandResult.new(object: scoped_object, display: self.display)
      end
    end
  end
end
