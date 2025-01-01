# typed: true
# frozen_string_literal: true

# Error indicating that a spammy user cannot create content.
class ContentAuthorizationError::SpammyCantDoThat < ContentAuthorizationError
  attr_accessor :verb, :subject

  def initialize(operation, subject)
    @verb    = operation
    @subject = subject
  end

  def message
    "Spammy users cannot #{verb} #{subject} they don't own."
  end
end
