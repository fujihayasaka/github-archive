# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class TeamProjectType < Platform::Enums::Base
      description "Defines which types of team projects are included in the returned list. Can be one of IMMEDIATE, INHERITED or ALL."
      visibility :internal

      value "IMMEDIATE", "Includes only immediate projects of the team.", value: "immediate"
      value "INHERITED", "Includes only inherited projects for the team.", value: "inherited"
      value "ALL", "Includes immediate and inherited projects for the team.", value: "all"
    end
  end
end
