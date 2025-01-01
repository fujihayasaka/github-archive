# typed: true
# frozen_string_literal: true

module TasklistBlocks
  class ValidationError
    sig { params(block: Integer, line: Integer, error: String).void }
    def initialize(block, line, error)
      @block = block
      @line = line
      @error = error
    end

    sig { returns(String) }
    def to_s
      "#{@error} at block #{@block + 1}, line #{@line + 1}"
    end
  end
end
