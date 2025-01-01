# typed: true
# frozen_string_literal: true

module Permissions
  module Attributes
    class Business < Default
      def subject_attributes
        super.merge(
          "subject.business.id" => participant.id
        )
      end

      def actor_attributes(actor)
        if actor.is_a?(::User) && participant.feature_enabled?(:enterprise_enforce_upfront_attribute)
          super.merge(
            "business.enterprise_teams.for_user" => EnterpriseTeam.all_visible_team_ids_for(actor, business_ids: [participant.id])
          )
        else
          super
        end
      end
    end
  end
end
