# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class OrganizationOrUser < Platform::Unions::Base
      description "Used for argument of CreateProjectV2 mutation."

      visibility :public, environments: [:dotcom, :enterprise]

      possible_types Objects::Organization, Objects::User
    end
  end
end
