# typed: strict
# frozen_string_literal: true

module Platform
  module Inputs
    class ProjectV2Collaborator < Platform::Inputs::Base
      description "A collaborator to update on a project. Only one of the userId or teamId should be provided."
      class Collaborator < T::Struct
        prop :user, T.nilable(User)
        prop :team, T.nilable(Team)
        prop :role, String
      end

      argument :user_id, ID, "The ID of the user as a collaborator.", required: false, loads: Objects::User
      argument :team_id, ID, "The ID of the team as a collaborator.", required: false, loads: Objects::Team

      argument :role, Platform::Enums::ProjectV2Roles, "The role to grant the collaborator", required: true
    end
  end
end
