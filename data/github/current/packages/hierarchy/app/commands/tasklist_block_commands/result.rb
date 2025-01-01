# typed: strict
# frozen_string_literal: true

module TasklistBlockCommands
  class Result
    extend T::Sig

    sig { returns(String) }
    attr_reader :message

    sig { params(success: T::Boolean, message: String).void }
    def initialize(success:, message: "")
      @success = success
      @message = message
    end

    # Public: was the result passed in a success?
    sig { returns(T::Boolean) }
    def success?
      @success
    end
  end
end
