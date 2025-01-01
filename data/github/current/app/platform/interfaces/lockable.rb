# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module Lockable
      include Platform::Interfaces::Base
      description "An object that can be locked."

      field :locked, Boolean, description: "`true` if the object is locked", null: false, method: :locked?

      field :active_lock_reason, Enums::LockReason, "Reason that the conversation was locked.", null: true

      def active_lock_reason
        if @object.is_a?(PullRequest)
          @object.async_issue.then(&:active_lock_reason)
        else
          @object.active_lock_reason
        end
      end
    end
  end
end
