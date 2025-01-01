# typed: strict
# frozen_string_literal: true

class MemexProjectWorkflow
  sig { returns T.nilable(::Integer) }
  def number; end

  sig { returns T.nilable(::String) }
  def trigger_type; end
end
