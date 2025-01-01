# typed: true
# frozen_string_literal: true

class Actions::Resolver::Success
  attr_reader :status, :body

  def initialize(status:, body:)
    @status = status
    @body = body
  end

  def success?
    true
  end
end
