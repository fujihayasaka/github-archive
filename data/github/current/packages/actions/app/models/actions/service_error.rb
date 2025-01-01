# typed: true
# frozen_string_literal: true

# A remote service call error
class Actions::ServiceError < StandardError
  attr_reader :status, :options

  def initialize(message, status:, options: {})
    super(message)
    @status  = status
    @options = options
  end
end
