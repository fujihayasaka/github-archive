# typed: strict
# frozen_string_literal: true

module Platform
  module Unions
    class ProjectV2Actor < Platform::Unions::Base
      description "Possible collaborators for a project."

      visibility :public, environments: [:dotcom, :enterprise]

      possible_types(
        Objects::Team,
        Objects::User
      )
    end
  end
end
