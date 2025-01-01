# typed: true
# frozen_string_literal: true

module Permissions
  module Enumerators
    class BelongToOrganization < Permissions::Enumerator
      def actor_ids
        Ability.where(
          actor_type: Enumerators::OwnOrganization::ACTOR_TYPE,
          subject_type: Enumerators::OwnOrganization::SUBJECT_TYPE,
          subject_id: subject_id,
          priority: Ability.priorities[:direct],
        ).pluck(:actor_id)
      end
    end
  end
end
