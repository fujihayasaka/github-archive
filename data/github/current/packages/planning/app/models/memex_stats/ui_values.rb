# typed: strict
# frozen_string_literal: true

module MemexStats
  # Represents valid values for logging UI context for the purposes of telemetry/stats
  class UIValues < T::Enum
    # NOTE: This is not a comprehensive list of all UI values that can be logged. However, if it is in this list,
    # then it is definitely a valid UI string value.
    enums do
      # Interaction from the team projects page
      TeamIndex = new("team_index")
      # Interaction from the organization projects page
      OrgIndex = new("org_index")
      # Interaction from the user projects page
      UserIndex = new("user_index")
      # Interaction from the repository projects page
      RepoIndex = new("repo_index")
    end
  end
end
