# typed: true
# frozen_string_literal: true

require "context"

module GitHub
  module Config
    module Context

      # The context for the current runtime environment, such as the action
      # being performed, the actor, the affected objects, etc.
      def context
        Thread.current[:github_context] ||= ::Context.new
      end

      def context=(val)
        Thread.current[:github_context] = val
      end
    end
  end

  extend Config::Context
end
