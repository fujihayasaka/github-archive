# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class RepositorySuggestedActorFilter < Platform::Enums::Base
      description "The possible filters for suggested actors in a repository"

      value "CAN_BE_ASSIGNED", "Actors that can be assigned to issues and pull requests", value: "can_be_assigned"
      value "CAN_BE_AUTHOR", "Actors that can be the author of issues and pull requests", value: "can_be_author"
    end
  end
end
