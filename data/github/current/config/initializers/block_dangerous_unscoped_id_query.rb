# typed: true
# frozen_string_literal: true

module BlockDangerousUnscopedIdQuery
  class DangerousUnscopedQueryError < RuntimeError ; end

  def self.extended(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    extend T::Helpers

    requires_ancestor { ActiveRecord::Base }

    # Never want this to run unscoped. See https://github.com/github/availability/issues/3768 for more context.
    def ids
      Kernel.raise DangerousUnscopedQueryError.new("Unscoped ids called")
    end
  end
end

ActiveSupport.on_load(:active_record) do
  extend BlockDangerousUnscopedIdQuery
end
