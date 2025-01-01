# typed: true
# frozen_string_literal: true

require "context"

module Audit
  module Context

    # The context for the current audit logging environment, such as the
    # request_id, the actor, etc. This context is specific to the audit log
    # and isolated from other contexts which may exist in the application.
    def context
      Thread.current[:audit_context] ||= ::Context.new
    end

    def context=(val)
      Thread.current[:audit_context] = val
    end
  end

  extend Context
end
