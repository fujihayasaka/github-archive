# typed: true
# frozen_string_literal: true

module TasklistBlockCommands
  class Result
    class SerializeFromBodyResult < TasklistBlockCommands::Result
      extend T::Sig

      attr_reader :data

      sig do
        params(
          success: T::Boolean,
          data: T.nilable(T::Array[Hash]),
          message: String
        ).void
      end
      def initialize(success:, data: nil, message: "")
        super(success: success, message: message)
        @data = data
      end
    end
  end
end
