# typed: true
# frozen_string_literal: true

module Permissions
  class Granter
    # Public: Grant permission for the actor_id to perform the action on the
    # subject_id.
    #
    # Returns a GrantResult.
    def self.grant(actor_id:, action:, subject_id:, entry_point: nil)
      granter = ActionGrants.lookup(action: action).new
      granter.grant!(actor_id: actor_id, subject_id: subject_id, entry_point: entry_point)
    end

    # Public: Revoke permission for the actor_id on the subject_id.
    #
    # Returns a GrantResult.
    def self.revoke(actor_id:, action:, subject_id:, entry_point: nil)
      granter = ActionGrants.lookup(action: action).new
      granter.revoke!(actor_id: actor_id, subject_id: subject_id, entry_point: entry_point)
    end

    class Noop < Granters::BaseGranter

      def initialize
        # no-op
      end

      def grant!(*args)
        GrantResult.failure!(reason: "Not a valid grant (Noop#grant!)")
      end

      def revoke!(*args)
        GrantResult.failure!(reason: "Not a valid grant (Noop#revoke!)")
      end
    end
  end
end
