# typed: true
# frozen_string_literal: true

# Error indicating that the project is locked.
class ContentAuthorizationError::ProjectLocked < ContentAuthorizationError
  attr_reader :lock_type

  def initialize(lock_type: "automation resync")
    @lock_type = lock_type
  end

  def symbolic_error_code
    :maintenance
  end

  def message
    "Project has been locked for #{lock_type}."
  end
end
