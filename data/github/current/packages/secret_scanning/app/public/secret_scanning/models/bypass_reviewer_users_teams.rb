# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Models
    class BypassReviewerUsersTeams < T::Struct
      const :users, T::Array[User]
      const :teams, T::Array[Team]
      const :business_teams, T::Array[BusinessTeam]
    end
  end
end
