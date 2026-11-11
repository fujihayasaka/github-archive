# typed: true
# frozen_string_literal: true

module TasklistBlockCommands
  class Result
    class ExtractPosition < TasklistBlockCommands::Result
      sig do
        params(
          success: T::Boolean,
          action: Symbol,
          data: T.nilable(T.any(Integer, T::Array[Integer])),
          message: String
        ).void
      end
      def initialize(success:, action:, data: nil, message: "")
        super(success: success, message: message)
        @action = action
        @data = data
      end

      sig { returns(T.nilable(T.any(Integer, T::Array[Integer], T::Array[T::Array[T.nilable(Integer)]]))) }
      def data
        # This seems _very_ redundant now but the next PR will add a new action
        # type and this is in preparation for that.
        case @action
        when :add then @data
        when :update_issue_position then build_update_position_params
        else @data
        end
      end

      sig { returns(T::Array[T::Array[T.nilable(Integer)]]) }
      private def build_update_position_params
        return [] unless @data
        block_position, source_position, destination_position = @data
        [
          [block_position, source_position],
          [block_position, destination_position],
        ]
      end
    end
  end
end
