# typed: true
# frozen_string_literal: true

module GitHub
  class DGit
    # Values for the state field
    ACTIVE     = 1
    FAILED     = 2
    CREATING   = 3
    DESTROYING = 4
    REPAIRING  = 5
    DORMANT    = 6
    NOT_DORMANT = [ACTIVE, FAILED, CREATING, DESTROYING, REPAIRING]
    # A map for showing human-readable names for state-field values
    STATES = {
      ACTIVE     => "ACTIVE",
      FAILED     => "FAILED",
      CREATING   => "CREATING",
      DESTROYING => "DESTROYING",
      REPAIRING  => "REPAIRING",
      DORMANT    => "DORMANT",
    }
  end
end
