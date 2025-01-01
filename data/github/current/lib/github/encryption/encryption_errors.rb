# typed: true
# frozen_string_literal: true

module GitHub
  module Encryption
    class KeyNotFoundError < RuntimeError; end
    class KeyConsistencyError < RuntimeError; end
    class KeyLengthError < RuntimeError; end
    class KeyEncodingError < RuntimeError; end
    class NotImplementedError < RuntimeError; end

    class InvalidSaltError < StandardError; end
  end
end
