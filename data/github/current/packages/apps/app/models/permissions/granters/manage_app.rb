# typed: true
# frozen_string_literal: true

module Permissions
  module Granters
    class ManageApp < BaseGranter
      ACTOR_TYPE = "User"
      ACTION = :admin
      ACTION_TO_INT = Ability.actions[ACTION]
      SUBJECT_TYPE = "Integration/manage"
      PRIORITY = Ability.priorities[:direct]

      def initialize
        super(actor_type: ACTOR_TYPE,
              action_int: ACTION_TO_INT,
              priority: PRIORITY,
              subject_type: SUBJECT_TYPE)
      end
    end
  end
end
