# typed: true
# frozen_string_literal: true

class Actions::Resolver::Error
  attr_reader :status, :msg

  def initialize(status:, msg:)
    @status = status
    @msg = msg
  end

  def success?
    false
  end
end
