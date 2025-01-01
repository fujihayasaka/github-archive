# typed: true
# frozen_string_literal: true

class Platform::Models::CodeSearchError
  attr_reader :message

  def initialize(message: "")
    @message = message.to_s
  end
end
