# typed: true
# frozen_string_literal: true

module Permissions
  module Granters
    class BaseGranter
      attr_reader :actor_type, :action_int, :priority, :subject_type, :context

      def initialize(actor_type:, action_int:, priority:, subject_type:, context: {})
        @actor_type = actor_type
        @action_int = action_int
        @priority = priority
        @subject_type = subject_type
        @context = context
      end

      def grant!(actor_id:, subject_id:, entry_point: nil)
        raise ArgumentError.new("actor_id and subject_id are required") unless actor_id && subject_id
        row = [
          actor_id,
          actor_type,
          action_int,
          subject_id,
          subject_type,
          priority,
          0,
          GitHub::SQL::ArelLiterals::NOW,
          GitHub::SQL::ArelLiterals::NOW,
          nil,
        ]

        if Permissions::Service.grant_permissions([row], stats_key: self.class.name, entry_point: entry_point)
          GrantResult.success!
        else
          GrantResult.failure!(reason: "Could not grant #{self.class.name} permission")
        end
      end

      def revoke!(actor_id:, subject_id:, entry_point: nil)
        raise ArgumentError.new("actor_id and subject_id are required") unless actor_id && subject_id
        args = {
          actor_id: actor_id,
          actor_type: actor_type,
          subject_id: subject_id,
          subject_type: subject_type,
          action: action_int,
          priority: priority,
          entry_point: entry_point,
        }

        if Permissions::Service.revoke_permissions(**args)
          GrantResult.success! # TODO: check this and handle async here
        else
          GrantResult.failure!(reason: "Failed to revoke #{self.class.name} permission on #{subject_id}")
        end
      end
    end
  end
end
