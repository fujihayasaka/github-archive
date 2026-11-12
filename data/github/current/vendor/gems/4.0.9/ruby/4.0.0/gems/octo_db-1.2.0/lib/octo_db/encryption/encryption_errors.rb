# typed: true
# frozen_string_literal: true

module OctoDb
  module Encryption
    class InvalidSaltError < StandardError; end
    class KeyNotFoundError < StandardError; end
    class KeyEncodingError < StandardError; end
    class KeyLengthError < StandardError; end
    class KeyConsistencyError < StandardError; end
    class NotImplementedError < StandardError; end
  end
end
