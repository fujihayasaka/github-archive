# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class TeamRepositoryType < Platform::Enums::Base
      description "Defines which types of team repositories are included in the returned list. Can be one of IMMEDIATE, INHERITED or ALL."
      visibility :internal

      value "IMMEDIATE", "Includes only immediate repositories of the team.", value: "immediate"
      value "INHERITED", "Includes only inherited repositories for the team.", value: "inherited"
      value "ALL", "Includes immediate and inherited repositories for the team.", value: "all"
    end
  end
end
