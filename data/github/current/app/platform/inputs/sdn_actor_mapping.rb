# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class SdnActorMapping < Platform::Inputs::Base
      graphql_name "SdnActorMapping"
      description "Specially Designated Nationals (SDN) mapping for users, organizations or enterprises."
      visibility :internal, environments: [:dotcom]

      argument :actor_id, ID, "ID of the actor.", required: true
      argument :actor_type, Platform::Enums::SdnActor, "Type of the actor, such as user, organization, or enterprise.", required: true
    end
  end
end
