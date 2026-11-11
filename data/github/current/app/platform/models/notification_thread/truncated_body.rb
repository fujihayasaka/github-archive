# typed: true
# frozen_string_literal: true

class Platform::Models::NotificationThread
  # Truncate a given body string
  class TruncatedBody
    LIMIT = 3.kilobytes

    sig { returns(String) }
    attr_reader :str

    sig { params(str: String).void }
    def initialize(str)
      @str = str
    end

    sig { returns(String) }
    def to_s
      str.to_s[0..LIMIT.to_i - 1].to_s
    end
  end
end
