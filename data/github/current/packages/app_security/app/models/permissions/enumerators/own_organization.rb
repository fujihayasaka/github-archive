# typed: true
# frozen_string_literal: true

module Permissions
  module Enumerators
    class OwnOrganization < Permissions::Enumerator
      ACTOR_TYPE = "User"
      SUBJECT_TYPE = "Organization"

      def actor_ids
        Ability.where(
          actor_type: ACTOR_TYPE,
          subject_type: SUBJECT_TYPE,
          subject_id: subject_id,
          action: Ability.actions[:admin],
          priority: Ability.priorities[:direct],
        ).pluck(:actor_id)
      end
    end
  end
end
