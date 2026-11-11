# typed: true
# frozen_string_literal: true

module TasklistBlockCommands
  class Result
    class CommandResult < TasklistBlockCommands::Result
      attr_reader :command

      sig do
        params(
          success: T::Boolean,
          command: T.nilable(Object),
          message: String
        ).void
      end
      def initialize(success:, command: nil, message: "")
        super(success: success, message: message)
        @command = command
      end
    end
  end
end
