# typed: true
# frozen_string_literal: true

class Actions::Proxima::WorkflowTemplatesError < StandardError
  def initialize(msg = "", url:, status:, body: nil, errors: nil)
    super(msg)
    @url = url
    @status = status
    @body = body
    @errors = errors
  end

  attr_reader :url, :status, :body, :errors
end
